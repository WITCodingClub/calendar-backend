# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: catalog_year_courses
#
#  id                :bigint           not null, primary key
#  course_number     :integer          not null
#  description       :text
#  max_credits       :integer
#  min_credits       :integer
#  prerequisite_text :text
#  subject_code      :string           not null
#  title             :string
#  typically_offered :string           default([]), not null, is an Array
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  catalog_course_id :bigint
#  catalog_year_id   :bigint           not null
#
# Indexes
#
#  idx_catalog_year_courses_unique                               (catalog_year_id,subject_code,course_number) UNIQUE
#  index_catalog_year_courses_on_catalog_course_id               (catalog_course_id)
#  index_catalog_year_courses_on_subject_code_and_course_number  (subject_code,course_number)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_course_id => catalog_courses.id) ON DELETE => nullify
#  fk_rails_...  (catalog_year_id => catalog_years.id) ON DELETE => cascade
#
RSpec.describe CatalogYearCourse do
  subject { create(:catalog_year_course) }

  it { is_expected.to belong_to(:catalog_year) }
  it { is_expected.to belong_to(:catalog_course).optional }
  it { is_expected.to validate_presence_of(:subject_code) }
  it { is_expected.to validate_presence_of(:course_number) }
  it { is_expected.to validate_uniqueness_of(:course_number).scoped_to(:catalog_year_id, :subject_code) }

  it "keeps the same course in two catalog years apart" do
    later = create(:catalog_year_course, subject_code: subject.subject_code, course_number: subject.course_number,
                                         title: "A NEW TITLE")

    expect(later).to be_persisted
    expect(subject.reload.title).not_to eq("A NEW TITLE")
  end

  # A comparison with another column, so the numericality matchers do not cover it.
  it "rejects a credit range that ends below its start" do
    expect(build(:catalog_year_course, min_credits: 4, max_credits: 3)).not_to be_valid
  end

  it "links to the Banner course with its code" do
    course = create(:catalog_course, subject_code: "COMP", course_number: 128)
    row = create(:catalog_year_course, subject_code: "COMP", course_number: 128)

    described_class.link_catalog_courses

    expect(row.reload.catalog_course).to eq(course)
  end

  it "keeps its row when the Banner course is deleted" do
    course = create(:catalog_course)
    subject.update!(catalog_course: course)

    course.destroy

    expect(subject.reload.catalog_course).to be_nil
  end
end
