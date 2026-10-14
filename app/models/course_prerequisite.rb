# frozen_string_literal: true

# One course that another course lists as a prerequisite. The tree in
# CatalogCourse#prerequisites says how the courses combine (and, or); these
# rows link each named course to its CatalogCourse, so a course can list what
# it unlocks. required_catalog_course is nil for a code that is not in the
# system, such as an old three-digit course number.
class CoursePrerequisite < ApplicationRecord
  belongs_to :catalog_course
  belongs_to :required_catalog_course, class_name: "CatalogCourse", optional: true, inverse_of: :required_by

  validates :required_subject_code, :required_course_number, presence: true
end
