# frozen_string_literal: true

# One course that another course lists as a prerequisite. The tree in
# CatalogCourse#prerequisites says how the courses combine (and, or); these
# rows link each named course to its CatalogCourse, so a course can list what
# it unlocks. required_catalog_course is nil for a code that is not in the
# system, such as an old three-digit course number.
# == Schema Information
#
# Table name: course_prerequisites
#
#  id                         :bigint           not null, primary key
#  min_grade                  :string
#  required_course_number     :integer          not null
#  required_subject_code      :string           not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  catalog_course_id          :bigint           not null
#  required_catalog_course_id :bigint
#
# Indexes
#
#  idx_on_required_subject_code_required_course_number_45b4b1b10c  (required_subject_code,required_course_number)
#  index_course_prerequisites_on_catalog_course_id                 (catalog_course_id)
#  index_course_prerequisites_on_required_catalog_course_id        (required_catalog_course_id)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_course_id => catalog_courses.id) ON DELETE => cascade
#  fk_rails_...  (required_catalog_course_id => catalog_courses.id) ON DELETE => nullify
#
class CoursePrerequisite < ApplicationRecord
  belongs_to :catalog_course
  belongs_to :required_catalog_course, class_name: "CatalogCourse", optional: true, inverse_of: :required_by

  validates :required_subject_code, :required_course_number, presence: true
end
