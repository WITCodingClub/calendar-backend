# frozen_string_literal: true

FactoryBot.define do
  factory :course_prerequisite do
    catalog_course
    required_catalog_course factory: :catalog_course
    required_subject_code { required_catalog_course&.subject_code || "COMP" }
    required_course_number { required_catalog_course&.course_number || 128 }
  end
end
