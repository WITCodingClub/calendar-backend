# frozen_string_literal: true

# == Schema Information
#
# Table name: final_exams
# Database name: primary
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
require "rails_helper"

RSpec.describe FinalExam, type: :model do
  describe "associations" do
    it { should belong_to(:course).optional }
    it { should belong_to(:term) }
  end

  describe "validations" do
    subject { build(:final_exam) }

    it { should validate_presence_of(:exam_date) }
    it { should validate_presence_of(:start_time) }
    it { should validate_presence_of(:end_time) }

    it { should validate_presence_of(:crn) }

    it "validates uniqueness of crn scoped to term_id" do
      existing = create(:final_exam)
      duplicate = build(:final_exam, crn: existing.crn, term: existing.term, course: nil)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:crn]).to include("can only have one final exam per CRN per term")
    end

    it "validates end_time is after start_time" do
      exam = build(:final_exam, start_time: 1000, end_time: 800)
      expect(exam).not_to be_valid
      expect(exam.errors[:end_time]).to include("must be after start time")
    end

    it "validates end_time equals start_time is invalid" do
      exam = build(:final_exam, start_time: 1000, end_time: 1000)
      expect(exam).not_to be_valid
    end
  end

  describe "time formatting methods" do
    let(:exam) { build(:final_exam, start_time: 800, end_time: 1030) }

    describe "#formatted_start_time" do
      it "formats time as HH:MM" do
        expect(exam.formatted_start_time).to eq("08:00")
      end

      it "handles afternoon times" do
        exam.start_time = 1330
        expect(exam.formatted_start_time).to eq("13:30")
      end

      it "returns nil for nil time" do
        exam.start_time = nil
        expect(exam.formatted_start_time).to be_nil
      end
    end

    describe "#formatted_end_time" do
      it "formats time as HH:MM" do
        expect(exam.formatted_end_time).to eq("10:30")
      end
    end

    describe "#formatted_start_time_ampm" do
      it "formats morning time with AM" do
        expect(exam.formatted_start_time_ampm).to eq("8:00 AM")
      end

      it "formats afternoon time with PM" do
        exam.start_time = 1400
        expect(exam.formatted_start_time_ampm).to eq("2:00 PM")
      end

      it "handles noon as 12:00 PM" do
        exam.start_time = 1200
        expect(exam.formatted_start_time_ampm).to eq("12:00 PM")
      end

      it "handles midnight as 12:00 AM" do
        exam.start_time = 0
        expect(exam.formatted_start_time_ampm).to eq("12:00 AM")
      end
    end

    describe "#formatted_end_time_ampm" do
      it "formats time with AM/PM" do
        expect(exam.formatted_end_time_ampm).to eq("10:30 AM")
      end
    end
  end

  describe "#duration_hours" do
    it "calculates correct duration for 2-hour exam" do
      exam = build(:final_exam, start_time: 800, end_time: 1000)
      expect(exam.duration_hours).to eq(2.0)
    end

    it "calculates correct duration with minutes" do
      exam = build(:final_exam, start_time: 800, end_time: 1030)
      expect(exam.duration_hours).to eq(2.5)
    end

    it "returns 0 when times are nil" do
      exam = build(:final_exam)
      exam.start_time = nil
      expect(exam.duration_hours).to eq(0)
    end
  end

  describe "#time_of_day" do
    it "returns 'morning' for early times" do
      expect(build(:final_exam, start_time: 800).time_of_day).to eq("morning")
      expect(build(:final_exam, start_time: 1100).time_of_day).to eq("morning")
    end

    it "returns 'afternoon' for midday times" do
      expect(build(:final_exam, start_time: 1200).time_of_day).to eq("afternoon")
      expect(build(:final_exam, start_time: 1600).time_of_day).to eq("afternoon")
    end

    it "returns 'evening' for late times" do
      expect(build(:final_exam, start_time: 1700).time_of_day).to eq("evening")
      expect(build(:final_exam, start_time: 2000).time_of_day).to eq("evening")
    end

    it "returns nil for nil start_time" do
      exam = build(:final_exam)
      exam.start_time = nil
      expect(exam.time_of_day).to be_nil
    end
  end

  describe "#course_code" do
    it "returns formatted course code" do
      course = build(:course, subject: "COMP", course_number: 1000, section_number: "01")
      exam = build(:final_exam, course: course)
      expect(exam.course_code).to eq("COMP-1000-01")
    end
  end

  describe "instructor methods" do
    let(:course) { create(:course) }
    let(:exam) { create(:final_exam, course: course) }

    describe "#primary_instructor" do
      it "returns first faculty name" do
        faculty = create(:faculty, first_name: "John", last_name: "Smith")
        course.faculties << faculty
        expect(exam.primary_instructor).to eq("John Smith")
      end

      it "returns TBA when no faculty" do
        expect(exam.primary_instructor).to eq("TBA")
      end
    end

    describe "#all_instructors" do
      it "returns all faculty names joined" do
        faculty1 = create(:faculty, first_name: "John", last_name: "Smith")
        faculty2 = create(:faculty, first_name: "Jane", last_name: "Doe")
        course.faculties << faculty1
        course.faculties << faculty2
        expect(exam.all_instructors).to eq("John Smith, Jane Doe")
      end

      it "returns TBA when no faculty" do
        expect(exam.all_instructors).to eq("TBA")
      end
    end
  end

  describe "#combined_crns_display" do
    it "returns combined CRNs as comma-separated string" do
      exam = build(:final_exam, :with_combined_crns)
      expect(exam.combined_crns_display).to eq("12345, 12346, 12347")
    end

    it "returns direct crn when combined_crns is nil" do
      exam = build(:final_exam, crn: 99999, combined_crns: nil)
      expect(exam.combined_crns_display).to eq("99999")
    end
  end

  describe "datetime methods" do
    let(:exam) do
      build(:final_exam,
            exam_date: Date.new(2025, 12, 16),
            start_time: 800,
            end_time: 1000)
    end

    describe "#start_datetime" do
      it "returns correct DateTime" do
        result = exam.start_datetime
        expect(result.year).to eq(2025)
        expect(result.month).to eq(12)
        expect(result.day).to eq(16)
        expect(result.hour).to eq(8)
        expect(result.min).to eq(0)
      end

      it "returns nil when exam_date is nil" do
        exam.exam_date = nil
        expect(exam.start_datetime).to be_nil
      end

      it "returns nil when start_time is nil" do
        exam.start_time = nil
        expect(exam.start_datetime).to be_nil
      end
    end

    describe "#end_datetime" do
      it "returns correct DateTime" do
        result = exam.end_datetime
        expect(result.year).to eq(2025)
        expect(result.month).to eq(12)
        expect(result.day).to eq(16)
        expect(result.hour).to eq(10)
        expect(result.min).to eq(0)
      end

      it "returns nil when exam_date is nil" do
        exam.exam_date = nil
        expect(exam.end_datetime).to be_nil
      end
    end
  end

  describe "delegated methods" do
    let(:course) do
      build(:course,
            title: "Introduction to Programming",
            subject: "COMP",
            course_number: 1000,
            section_number: "01",
            crn: 12345,
            schedule_type: "lecture")
    end
    let(:exam) { build(:final_exam, course: course) }

    it "delegates title to course" do
      expect(exam.course_title).to eq("Introduction to Programming")
    end

    it "delegates subject to course" do
      expect(exam.course_subject).to eq("COMP")
    end

    it "delegates course_number to course" do
      expect(exam.course_course_number).to eq(1000)
    end

    it "delegates section_number to course" do
      expect(exam.course_section_number).to eq("01")
    end

    it "delegates schedule_type to course" do
      expect(exam.course_schedule_type).to eq("lecture")
    end
  end

  describe "orphan/linked exams" do
    describe "scopes" do
      let(:term) { create(:term) }
      let(:linked_exam) { create(:final_exam, term: term) }
      let(:orphan_exam) { create(:final_exam, :orphan, term: term) }

      before do
        linked_exam
        orphan_exam
      end

      it "orphan scope returns exams without courses" do
        expect(FinalExam.orphan).to include(orphan_exam)
        expect(FinalExam.orphan).not_to include(linked_exam)
      end

      it "linked scope returns exams with courses" do
        expect(FinalExam.linked).to include(linked_exam)
        expect(FinalExam.linked).not_to include(orphan_exam)
      end
    end

    describe "#orphan? and #linked?" do
      it "returns true for orphan exam" do
        exam = build(:final_exam, :orphan)
        expect(exam.orphan?).to be true
        expect(exam.linked?).to be false
      end

      it "returns true for linked exam" do
        exam = build(:final_exam)
        expect(exam.linked?).to be true
        expect(exam.orphan?).to be false
      end
    end

    describe "#link_to_course!" do
      let(:term) { create(:term) }
      let(:course) { create(:course, crn: 55555, term: term) }
      let(:orphan_exam) { create(:final_exam, :orphan, crn: 55555, term: term) }

      it "links orphan exam to matching course" do
        course # create the course
        expect { orphan_exam.link_to_course! }.to change { orphan_exam.reload.course }.from(nil).to(course)
      end

      it "returns nil if no matching course" do
        exam = create(:final_exam, :orphan, crn: 99999, term: term)
        expect(exam.link_to_course!).to be_nil
      end
    end

    describe ".link_orphan_exams_to_courses" do
      let(:term) { create(:term) }
      let(:course1) { create(:course, crn: 11111, term: term) }
      let(:course2) { create(:course, crn: 22222, term: term) }

      it "links all orphan exams with matching courses" do
        course1
        course2
        orphan1 = create(:final_exam, :orphan, crn: 11111, term: term)
        orphan2 = create(:final_exam, :orphan, crn: 22222, term: term)
        orphan3 = create(:final_exam, :orphan, crn: 33333, term: term)

        linked_count = FinalExam.link_orphan_exams_to_courses(term: term)

        expect(linked_count).to eq(2)
        expect(orphan1.reload.course).to eq(course1)
        expect(orphan2.reload.course).to eq(course2)
        expect(orphan3.reload.course).to be_nil
      end
    end

    describe "#course_code for orphan exam" do
      it "returns CRN when no course is linked" do
        exam = build(:final_exam, :orphan, crn: 12345)
        expect(exam.course_code).to eq("CRN 12345")
      end
    end
  end

  describe "combined_crns serialization" do
    it "stores array as JSON" do
      exam = create(:final_exam, combined_crns: [12345, 12346])
      exam.reload
      expect(exam.combined_crns).to eq([12345, 12346])
    end

    it "handles nil" do
      exam = create(:final_exam, combined_crns: nil)
      exam.reload
      expect(exam.combined_crns).to be_nil
    end

    it "handles empty array" do
      exam = create(:final_exam, combined_crns: [])
      exam.reload
      expect(exam.combined_crns).to eq([])
    end
  end
end
