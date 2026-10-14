# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogCourse do
  subject { create(:catalog_course) }

  it { is_expected.to belong_to(:source_term).class_name("Term").optional }
  it { is_expected.to have_many(:course_prerequisites).dependent(:delete_all) }
  it { is_expected.to have_many(:prerequisite_courses).through(:course_prerequisites) }
  it { is_expected.to have_many(:required_by).class_name("CoursePrerequisite").with_foreign_key(:required_catalog_course_id).dependent(:nullify) }
  it { is_expected.to have_many(:unlocks).through(:required_by) }
  it { is_expected.to validate_presence_of(:subject_code) }
  it { is_expected.to validate_presence_of(:course_number) }
  it { is_expected.to validate_uniqueness_of(:course_number).scoped_to(:subject_code) }

  describe ".parse_code" do
    it "reads the common spellings" do
      expect(described_class.parse_code("COMP2350")).to eq([ "COMP", 2350 ])
      expect(described_class.parse_code(" comp 2350 ")).to eq([ "COMP", 2350 ])
      expect(described_class.parse_code("COMP-128")).to eq([ "COMP", 128 ])
    end

    it "returns nil for anything else" do
      expect(described_class.parse_code("2350")).to be_nil
      expect(described_class.parse_code("COMP 23500")).to be_nil
    end
  end

  it "finds a course by code" do
    expect(described_class.find_by_code("comp #{subject.course_number}")).to eq(subject)
    expect(described_class.find_by_code("nonsense")).to be_nil
  end

  # A callback, so no matcher covers it.
  it "stores the subject code in capitals" do
    expect(create(:catalog_course, subject_code: " math ").subject_code).to eq("MATH")
  end

  it "names the courses it unlocks" do
    later = create(:catalog_course)
    create(:course_prerequisite, catalog_course: later, required_catalog_course: subject)

    expect(subject.unlocks).to eq([ later ])
    expect(later.prerequisite_courses).to eq([ subject ])
  end

  it "lists its sections in a term" do
    term = create(:term)
    section = create(:course, term: term, subject: "Computer Science (COMP)", course_number: subject.course_number)

    expect(subject.sections_in(term)).to eq([ section ])
  end
end
