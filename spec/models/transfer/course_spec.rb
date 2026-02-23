# frozen_string_literal: true

# == Schema Information
#
# Table name: transfer_courses
# Database name: primary
#
#  id            :bigint           not null, primary key
#  active        :boolean          default(TRUE), not null
#  course_code   :string           not null
#  course_title  :string           not null
#  credits       :decimal(5, 2)
#  description   :text
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  university_id :bigint           not null
#
# Indexes
#
#  index_transfer_courses_on_active                         (active)
#  index_transfer_courses_on_university_id                  (university_id)
#  index_transfer_courses_on_university_id_and_course_code  (university_id,course_code) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (university_id => transfer_universities.id)
#
require "rails_helper"

RSpec.describe Transfer::Course do
  describe "validations" do
    subject { build(:transfer_course) }

    it { is_expected.to validate_presence_of(:course_code) }
    it { is_expected.to validate_presence_of(:course_title) }

    describe "course_code uniqueness" do
      let(:university) { create(:transfer_university) }

      before { create(:transfer_course, university: university, course_code: "CS101") }

      it "validates uniqueness of course_code scoped to university_id" do
        duplicate = build(:transfer_course, university: university, course_code: "CS101")
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:course_code]).to be_present
      end

      it "allows same course code for different universities" do
        other_university = create(:transfer_university)
        other_course = build(:transfer_course, university: other_university, course_code: "CS101")
        expect(other_course).to be_valid
      end
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:university).class_name("Transfer::University") }
    it { is_expected.to have_many(:transfer_equivalencies).class_name("Transfer::Equivalency").with_foreign_key("transfer_course_id").dependent(:destroy) }
    it { is_expected.to have_many(:wit_courses).through(:transfer_equivalencies).source(:wit_course) }
  end

  describe "scopes" do
    let!(:active_course) { create(:transfer_course, active: true) }
    let!(:inactive_course) { create(:transfer_course, :inactive) }
    let(:university) { create(:transfer_university) }
    let!(:university_course) { create(:transfer_course, university: university) }

    describe ".active" do
      it "returns only active courses" do
        expect(described_class.active).to include(active_course)
        expect(described_class.active).not_to include(inactive_course)
      end
    end

    describe ".by_university" do
      it "returns courses for the specified university" do
        expect(described_class.by_university(university)).to include(university_course)
        expect(described_class.by_university(university)).not_to include(active_course)
      end
    end
  end

  describe "#course_identifier" do
    it "returns formatted course identifier" do
      course = create(:transfer_course, course_code: "CS101", course_title: "Introduction to CS")
      expect(course.course_identifier).to eq("CS101 - Introduction to CS")
    end
  end

  describe "#has_equivalencies?" do
    let(:course) { create(:transfer_course) }

    it "returns true when course has equivalencies" do
      create(:transfer_equivalency, transfer_course: course)
      expect(course.has_equivalencies?).to be true
    end

    it "returns false when course has no equivalencies" do
      expect(course.has_equivalencies?).to be false
    end
  end
end
