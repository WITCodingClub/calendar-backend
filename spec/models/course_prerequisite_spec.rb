# frozen_string_literal: true

require "rails_helper"

RSpec.describe CoursePrerequisite do
  it { is_expected.to belong_to(:catalog_course) }
  it { is_expected.to belong_to(:required_catalog_course).class_name("CatalogCourse").optional }
  it { is_expected.to validate_presence_of(:required_subject_code) }
  it { is_expected.to validate_presence_of(:required_course_number) }
end
