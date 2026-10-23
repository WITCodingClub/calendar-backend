# frozen_string_literal: true

# One course as one catalog year printed it: title, description, credits,
# and the prerequisite text. CatalogCourse holds what Banner says now. This
# row keeps what the catalog said that year, also for a course that Banner
# no longer lists.
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
class CatalogYearCourse < ApplicationRecord
  include CatalogCourseLinkable

  belongs_to :catalog_year

  validates :subject_code, :course_number, presence: true
  validates :course_number, uniqueness: { scope: [ :catalog_year_id, :subject_code ] }
  validates :max_credits, comparison: { greater_than_or_equal_to: :min_credits }, allow_nil: true, if: :min_credits
end
