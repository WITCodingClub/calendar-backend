# frozen_string_literal: true

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
FactoryBot.define do
  factory :course_faculty, class: "CourseFaculty" do
    association :course
    association :faculty
    primary_indicator { false }
  end
end
