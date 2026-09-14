# frozen_string_literal: true

FactoryBot.define do
  factory :course_faculty, class: "CourseFaculty" do
    association :course
    association :faculty
    primary_indicator { false }
  end
end
