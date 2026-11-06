# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: catalog_courses
#
#  id                  :bigint           not null, primary key
#  college             :string
#  corequisites        :jsonb            not null
#  course_number       :integer          not null
#  credit_hours        :integer
#  department          :string
#  description         :text
#  details_fetched_at  :datetime
#  division            :string
#  embedding           :vector(1536)
#  embedding_digest    :string(64)
#  fees                :jsonb            not null
#  grading_modes       :string           default([]), not null, is an Array
#  learning_objectives :text
#  levels              :string           default([]), not null, is an Array
#  mutual_exclusions   :jsonb            not null
#  prerequisites       :jsonb
#  restrictions        :jsonb            not null
#  subject_code        :string           not null
#  title               :string
#  typically_offered   :string           default([]), not null, is an Array
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  source_term_id      :bigint
#
# Indexes
#
#  index_catalog_courses_on_embedding                       (embedding vector_cosine_ops) USING hnsw
#  index_catalog_courses_on_source_term_id                  (source_term_id)
#  index_catalog_courses_on_subject_code_and_course_number  (subject_code,course_number) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (source_term_id => terms.id)
#
RSpec.describe CatalogCourse do
  subject { create(:catalog_course) }

  it { is_expected.to belong_to(:source_term).class_name("Term").optional }
  it { is_expected.to have_many(:course_prerequisites).dependent(:delete_all) }
  it { is_expected.to have_many(:prerequisite_courses).through(:course_prerequisites) }
  it { is_expected.to have_many(:required_by).class_name("CoursePrerequisite").with_foreign_key(:required_catalog_course_id).dependent(:nullify) }
  it { is_expected.to have_many(:unlocks).through(:required_by) }
  it { is_expected.to have_many(:catalog_year_courses).dependent(:nullify) }
  it { is_expected.to have_many(:program_plan_items).dependent(:nullify) }
  it { is_expected.to have_many(:elective_group_courses).dependent(:nullify) }
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

  describe "#embedding_text" do
    it "reads the course the way a student would describe it" do
      course = build(:catalog_course, subject_code: "COMP", course_number: 2350, title: "Databases",
                                      description: "Relational design and SQL.",
                                      learning_objectives: "Design a schema.\n  Write joins.",
                                      department: "Computer Science", college: "Computing and Data Science")

      expect(course.embedding_text).to eq(
        "COMP 2350 Databases\nRelational design and SQL.\nDesign a schema. Write joins.\n" \
        "Computer Science\nComputing and Data Science"
      )
    end

    it "takes the title and description from the newest catalog year when Banner has none" do
      course = create(:catalog_course, title: nil, description: nil)
      older  = create(:catalog_year, start_year: 2023)
      newer  = create(:catalog_year, start_year: 2025)
      [ [ older, "OLD", "Old text." ], [ newer, "NEW", "New text." ] ].each do |year, title, description|
        create(:catalog_year_course, catalog_year: year, subject_code: course.subject_code,
                                     course_number: course.course_number, title: title, description: description)
      end
      CatalogYearCourse.link_catalog_courses

      expect(course.reload.embedding_text).to eq("#{course.code} NEW\nNew text.")
    end

    it "keeps only the start of long learning objectives" do
      course = build(:catalog_course, learning_objectives: "word " * 1_000)

      objectives = course.embedding_text.lines.last
      expect(objectives.length).to be <= described_class::OBJECTIVES_LIMIT
    end
  end
end
