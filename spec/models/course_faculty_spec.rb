# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: courses_faculties
#
#  id                :bigint           not null, primary key
#  primary_indicator :boolean          default(FALSE), not null
#  course_id         :bigint           not null
#  faculty_id        :bigint           not null
#
# Indexes
#
#  index_courses_faculties_on_course_id                 (course_id)
#  index_courses_faculties_on_course_id_and_faculty_id  (course_id,faculty_id) UNIQUE
#  index_courses_faculties_on_course_id_and_primary     (course_id,primary_indicator)
#  index_courses_faculties_on_faculty_id                (faculty_id)
#
RSpec.describe CourseFaculty, type: :model do
  it { is_expected.to belong_to(:course) }
  it { is_expected.to belong_to(:faculty) }
end
