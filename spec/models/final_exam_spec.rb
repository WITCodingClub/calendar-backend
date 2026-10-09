# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: final_exams
#
#  id            :bigint           not null, primary key
#  combined_crns :text
#  crn           :integer
#  end_time      :integer          not null
#  exam_date     :date             not null
#  location      :string
#  notes         :text
#  start_time    :integer          not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  course_id     :bigint
#  term_id       :bigint           not null
#
# Indexes
#
#  index_final_exams_on_course_id        (course_id)
#  index_final_exams_on_crn_and_term_id  (crn,term_id) UNIQUE
#  index_final_exams_on_term_id          (term_id)
#
# Foreign Keys
#
#  fk_rails_...  (course_id => courses.id)
#  fk_rails_...  (term_id => terms.id)
#
RSpec.describe FinalExam do
  describe "associations and validations" do
    subject { create(:final_exam) }

    it { is_expected.to belong_to(:term) }
    it { is_expected.to belong_to(:course).optional }
    it { is_expected.to have_many(:calendar_events).dependent(:nullify) }

    it { is_expected.to validate_presence_of(:crn) }
    it { is_expected.to validate_presence_of(:exam_date) }
    it { is_expected.to validate_presence_of(:start_time) }
    it { is_expected.to validate_presence_of(:end_time) }
    it do
      expect(subject).to validate_uniqueness_of(:crn)
        .scoped_to(:term_id)
        .with_message("can only have one final exam per CRN per term")
    end

    # #end_time_after_start_time is a custom cross-field validation, not a
    # one-liner (validate_numericality_of has no "relative to another
    # attribute" comparison).
  end

  describe "#combined_crns" do
    it "returns an Array when the value is an Array" do
      exam = described_class.new(crn: 11111, combined_crns: [ 11111, 22222 ])

      expect(exam.combined_crns).to eq([ 11111, 22222 ])
    end

    it "decodes a double-encoded JSON string from the backend import" do
      exam = described_class.new(crn: 11111, combined_crns: "[11111, 22222]")

      expect(exam.combined_crns).to eq([ 11111, 22222 ])
    end

    it "splits a plain string that is not JSON" do
      exam = described_class.new(crn: 11111, combined_crns: "11111, 22222")

      expect(exam.combined_crns).to eq(%w[11111 22222])
    end

    it "returns nil when the value is nil" do
      exam = described_class.new(crn: 11111, combined_crns: nil)

      expect(exam.combined_crns).to be_nil
    end
  end

  describe "#combined_crns_display" do
    it "joins a double-encoded JSON string without an error" do
      exam = described_class.new(crn: 11111, combined_crns: "[11111, 22222]")

      expect(exam.combined_crns_display).to eq("11111, 22222")
    end

    it "falls back to the crn when combined_crns is nil" do
      exam = described_class.new(crn: 11111, combined_crns: nil)

      expect(exam.combined_crns_display).to eq("11111")
    end
  end

  describe "end time validation" do
    # Custom cross-field validation: no shoulda matcher compares two attributes.
    it "is invalid when the end is not after the start" do
      exam = build(:final_exam, start_time: 1000, end_time: 1000)

      expect(exam).not_to be_valid
      expect(exam.errors[:end_time]).to include("must be after start time")
    end

    it "is valid when the end is after the start" do
      expect(build(:final_exam, start_time: 800, end_time: 1000)).to be_valid
    end
  end

  describe "scopes" do
    include ActiveSupport::Testing::TimeHelpers

    let(:term) { create(:term) }

    it ".orphan and .linked split exams by course" do
      linked = create(:final_exam, term: term, course: create(:course, term: term))
      orphan = create(:final_exam, term: term)

      expect(described_class.linked).to contain_exactly(linked)
      expect(described_class.orphan).to contain_exactly(orphan)
    end

    it ".for_crn returns the exam of one crn" do
      match = create(:final_exam, term: term, crn: 81_111)
      create(:final_exam, term: term, crn: 82_222)

      expect(described_class.for_crn(81_111)).to contain_exactly(match)
    end

    it ".upcoming includes today and later" do
      travel_to(Date.new(2026, 12, 10)) do
        today = create(:final_exam, term: term, exam_date: Date.new(2026, 12, 10))
        later = create(:final_exam, term: term, exam_date: Date.new(2026, 12, 15))
        create(:final_exam, term: term, exam_date: Date.new(2026, 12, 9))

        expect(described_class.upcoming).to contain_exactly(today, later)
      end
    end
  end

  describe ".link_orphan_exams_to_courses" do
    let(:term) { create(:term) }

    it "links orphan exams that have a course with the same crn and term" do
      course = create(:course, term: term, crn: 83_333)
      match = create(:final_exam, term: term, crn: 83_333)
      other = create(:final_exam, term: term, crn: 84_444)

      expect(described_class.link_orphan_exams_to_courses(term: term)).to eq(1)
      expect(match.reload.course).to eq(course)
      expect(other.reload.course).to be_nil
    end

    it "ignores a course with the same crn in another term" do
      create(:course, crn: 83_333)
      create(:final_exam, term: term, crn: 83_333)

      expect(described_class.link_orphan_exams_to_courses(term: term)).to eq(0)
    end
  end

  describe "#link_to_course!" do
    let(:term) { create(:term) }

    it "links the course and returns it" do
      course = create(:course, term: term, crn: 85_555)
      exam = create(:final_exam, term: term, crn: 85_555)

      expect(exam.link_to_course!).to eq(course)
      expect(exam.reload.course).to eq(course)
    end

    it "returns nil when no course matches" do
      exam = create(:final_exam, term: term)

      expect(exam.link_to_course!).to be_nil
      expect(exam.reload).to be_orphan
    end

    it "does nothing when the exam already has a course" do
      exam = create(:final_exam, term: term, course: create(:course, term: term))

      expect(exam.link_to_course!).to be_nil
    end
  end

  describe "linked? and orphan?" do
    it "reflect the course" do
      linked = build(:final_exam, course: build(:course))
      orphan = build(:final_exam)

      expect([ linked.linked?, linked.orphan? ]).to eq([ true, false ])
      expect([ orphan.linked?, orphan.orphan? ]).to eq([ false, true ])
    end
  end

  describe "time formatting" do
    let(:exam) { build(:final_exam, start_time: 805, end_time: 1530) }

    it "formats 24-hour times" do
      expect([ exam.formatted_start_time, exam.formatted_end_time ]).to eq([ "08:05", "15:30" ])
    end

    it "formats 12-hour times" do
      expect([ exam.formatted_start_time_ampm, exam.formatted_end_time_ampm ]).to eq([ "8:05 AM", "3:30 PM" ])
    end

    it "shows midnight and noon as 12" do
      expect(build(:final_exam, start_time: 0).formatted_start_time_ampm).to eq("12:00 AM")
      expect(build(:final_exam, start_time: 1200).formatted_start_time_ampm).to eq("12:00 PM")
    end

    it "returns nil for a missing time" do
      blank = build(:final_exam, start_time: nil, end_time: nil)

      expect([ blank.formatted_start_time, blank.formatted_end_time_ampm ]).to eq([ nil, nil ])
    end
  end

  describe "#duration_hours" do
    it "counts hours and minutes" do
      expect(build(:final_exam, start_time: 830, end_time: 1115).duration_hours).to eq(2.75)
    end

    it "is 0 without times" do
      expect(build(:final_exam, start_time: nil, end_time: nil).duration_hours).to eq(0)
    end
  end

  describe "#time_of_day" do
    it "names the part of the day" do
      expect(build(:final_exam, start_time: 800).time_of_day).to eq("morning")
      expect(build(:final_exam, start_time: 1300).time_of_day).to eq("afternoon")
      expect(build(:final_exam, start_time: 1800).time_of_day).to eq("evening")
    end

    it "is nil without a start time" do
      expect(build(:final_exam, start_time: nil).time_of_day).to be_nil
    end
  end

  describe "course details" do
    it "#course_code falls back to the crn" do
      expect(build(:final_exam, crn: 86_666).course_code).to eq("CRN 86666")
    end

    it "#course_code joins the course parts" do
      course = build(:course, subject: "COMP", course_number: 1050, section_number: "02")

      expect(build(:final_exam, course: course).course_code).to eq("COMP-1050-02")
    end

    it "delegates course fields with a prefix" do
      exam = build(:final_exam, course: build(:course, title: "Intro Course", subject: "MATH"))

      expect([ exam.course_title, exam.course_subject ]).to eq([ "Intro Course", "MATH" ])
      expect(build(:final_exam).course_title).to be_nil
    end

    context "with instructors" do
      let(:course) { create(:course) }
      let(:exam) { create(:final_exam, term: course.term, course: course) }

      it "returns TBA without a course or instructors" do
        expect([ build(:final_exam).primary_instructor, build(:final_exam).all_instructors ]).to eq([ "TBA", "TBA" ])
        expect([ exam.primary_instructor, exam.all_instructors ]).to eq([ "TBA", "TBA" ])
      end

      it "names the instructors" do
        course.faculties << create(:faculty, first_name: "Ada", last_name: "Lovelace", display_name: nil)
        course.faculties << create(:faculty, first_name: "Alan", last_name: "Turing", display_name: nil)

        expect(exam.primary_instructor).to eq("Ada Lovelace")
        expect(exam.all_instructors).to eq("Ada Lovelace, Alan Turing")
      end
    end
  end

  describe "datetimes" do
    it "combine the exam date and the times" do
      exam = build(:final_exam, exam_date: Date.new(2026, 12, 17), start_time: 1330, end_time: 1530)

      expect(exam.start_datetime).to eq(Time.zone.local(2026, 12, 17, 13, 30))
      expect(exam.end_datetime).to eq(Time.zone.local(2026, 12, 17, 15, 30))
    end

    it "are nil without a date or time" do
      exam = build(:final_exam, exam_date: nil, start_time: nil, end_time: nil)

      expect([ exam.start_datetime, exam.end_datetime ]).to eq([ nil, nil ])
    end
  end

  describe "room matching" do
    # Abbreviations avoid digits (the matcher reads letters) and fixture names.
    let!(:building) { create(:building, abbreviation: "ZZQ", name: "Synthetic Hall") }
    let!(:room) { create(:room, building: building, number: "112") }
    let!(:lab) { create(:room, building: building, number: "205") }

    it "returns no rooms without a location" do
      exam = build(:final_exam, location: nil)

      expect(exam.matched_rooms).to eq([])
      expect(exam.rooms_matched?).to be(false)
      expect(exam.location_with_names).to be_nil
    end

    it "returns no rooms when the location has no room pattern" do
      expect(build(:final_exam, location: "Online").matched_rooms).to eq([])
    end

    it "finds rooms in a combined location" do
      exam = build(:final_exam, location: "ZZQ 112 / ZZQ 205")

      expect(exam.matched_rooms).to eq([ room, lab ])
      expect(exam.rooms_matched?).to be(true)
    end

    it "skips an unknown building or room" do
      exam = build(:final_exam, location: "NOPE 112 / ZZQ 999 / ZZQ 112")

      expect(exam.matched_rooms).to eq([ room ])
    end

    it "builds a location with building names" do
      exam = build(:final_exam, location: "ZZQ 112")

      expect(exam.location_with_names).to eq("Synthetic Hall 112")
    end

    it "matches a room with a letter suffix" do
      lettered = create(:room, building: building, number: "402A")
      create(:room, building: building, number: "402")
      exam = build(:final_exam, location: "ZZQ 402A")

      expect(exam.matched_rooms).to eq([ lettered ])
    end

    it "matches a room that the catalog stores with leading zeros" do
      padded = create(:room, building: building, number: "011")
      exam = build(:final_exam, location: "ZZQ 11")

      expect(exam.matched_rooms).to eq([ padded ])
    end

    it "keeps the raw location when no room matches" do
      exam = build(:final_exam, location: "NOPE 112")

      expect(exam.location_with_names).to eq("NOPE 112")
    end
  end
end
