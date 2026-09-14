# frozen_string_literal: true

# == Schema Information
#
# Table name: courses
#
#  id                :bigint           not null, primary key
#  course_number     :integer          not null
#  credit_hours      :integer
#  crn               :integer          not null
#  end_date          :date             not null
#  grade_mode        :string
#  is_section_linked :boolean          default(FALSE), not null
#  link_identifier   :string
#  schedule_type     :string           not null
#  seats_available   :integer
#  seats_capacity    :integer
#  section_number    :string           not null
#  start_date        :date             not null
#  status            :string           default("active"), not null
#  subject           :string           not null
#  title             :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  term_id           :bigint           not null
#
# Indexes
#
#  index_courses_on_course_and_link_identifier  (term_id,subject,course_number,link_identifier)
#  index_courses_on_crn_and_term_id             (crn,term_id) UNIQUE
#  index_courses_on_status                      (status)
#  index_courses_on_term_id                     (term_id)
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#
require "rails_helper"

RSpec.describe Course, type: :model do
  describe "associations and validations" do
    subject { create(:course) }

    it { is_expected.to belong_to(:term) }
    it { is_expected.to have_many(:course_faculties).dependent(:destroy) }
    it { is_expected.to have_many(:faculties).through(:course_faculties) }
    it { is_expected.to have_many(:meeting_times).class_name("Course::MeetingTime").dependent(:destroy) }
    it { is_expected.to have_many(:meeting_time_rooms).through(:meeting_times) }
    it { is_expected.to have_many(:rooms).through(:meeting_time_rooms) }
    it { is_expected.to have_many(:enrollments).dependent(:destroy) }
    it { is_expected.to have_many(:users).through(:enrollments) }
    it { is_expected.to have_one(:final_exam).dependent(:destroy) }

    # allow_nil isn't checked here: the model validation allows a nil crn, but
    # the courses.crn column is NOT NULL at the database level, so the model's
    # allow_nil: true can never actually be exercised (a nil crn fails at the
    # database before the validation would waive it). Worth a look as a
    # possible model bug.
    it do
      expect(subject).to validate_uniqueness_of(:crn)
        .scoped_to(:term_id)
        .with_message("has already been taken for this term")
    end

    it { is_expected.to define_enum_for(:status).with_values(active: "active", cancelled: "cancelled").backed_by_column_of_type(:string) }

    it do
      expect(subject).to define_enum_for(:schedule_type)
        .with_values(
          extension: "EXT", hybrid: "HYB", independent_study: "IND", laboratory: "LAB",
          lecture: "LEC", online: "ONL", online_blended: "ONB", online_sync_lab: "OLB",
          online_sync_lecture: "OLC", rotating_lab: "RLB", rotating_lecture: "RLC",
          study_abroad: "SAB", study_away_domestic: "SAD"
        )
        .backed_by_column_of_type(:string)
    end
  end

  let(:term) { create(:term) }

  def course(section_number:, schedule_type: "LEC", link_identifier: nil, subject: "CHEM", course_number: 1000)
    create(:course,
           term: term,
           subject: subject,
           course_number: course_number,
           section_number: section_number,
           schedule_type: schedule_type,
           link_identifier: link_identifier,
           is_section_linked: link_identifier.present?)
  end

  describe "#link_slot and #link_key" do
    it "splits the Banner identifier into the slot and the key" do
      lecture = course(section_number: "1A", link_identifier: "A1")

      expect(lecture.link_slot).to eq("A")
      expect(lecture.link_key).to eq("1")
    end

    it "keeps a key that is more than one character" do
      lecture = course(section_number: "1A", link_identifier: "AAB")

      expect(lecture.link_slot).to eq("A")
      expect(lecture.link_key).to eq("AB")
    end

    it "returns nil when the section is not linked" do
      lecture = course(section_number: "01")

      expect(lecture.link_slot).to be_nil
      expect(lecture.link_key).to be_nil
    end

    it "returns nil for a key when the identifier is only a slot" do
      lecture = course(section_number: "01", link_identifier: "A")

      expect(lecture.link_slot).to eq("A")
      expect(lecture.link_key).to be_nil
    end
  end

  describe "#linked_sections" do
    it "finds the labs that go with a lecture" do
      lecture = course(section_number: "1A", link_identifier: "A1")
      lab_one = course(section_number: "2A", schedule_type: "LAB", link_identifier: "B1")
      lab_two = course(section_number: "3A", schedule_type: "LAB", link_identifier: "B1")

      expect(lecture.linked_sections).to contain_exactly(lab_one, lab_two)
    end

    it "finds the lecture that goes with a lab" do
      lecture = course(section_number: "1A", link_identifier: "A1")
      lab     = course(section_number: "2A", schedule_type: "LAB", link_identifier: "B1")

      expect(lab.linked_sections).to contain_exactly(lecture)
    end

    it "does not cross keys" do
      lecture = course(section_number: "1A", link_identifier: "A1")
      course(section_number: "5B", schedule_type: "LAB", link_identifier: "B2")

      expect(lecture.linked_sections).to be_empty
    end

    it "does not return another section in the same slot" do
      lecture = course(section_number: "1A", link_identifier: "A1")
      course(section_number: "2A", link_identifier: "A1")

      expect(lecture.linked_sections).to be_empty
    end

    it "does not cross courses" do
      lecture = course(section_number: "1A", link_identifier: "A1")
      course(section_number: "2A", schedule_type: "LAB", link_identifier: "B1",
             subject: "PHYS", course_number: 1000)

      expect(lecture.linked_sections).to be_empty
    end

    it "leaves out cancelled sections" do
      lecture = course(section_number: "1A", link_identifier: "A1")
      lab     = course(section_number: "2A", schedule_type: "LAB", link_identifier: "B1")
      lab.update!(status: :cancelled)

      expect(lecture.linked_sections).to be_empty
    end

    it "returns none when the section is not linked" do
      lecture = course(section_number: "01")
      course(section_number: "02", schedule_type: "LAB", link_identifier: "B1")

      expect(lecture.linked_sections).to be_empty
    end
  end
end
