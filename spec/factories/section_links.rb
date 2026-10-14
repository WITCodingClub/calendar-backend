# frozen_string_literal: true

FactoryBot.define do
  factory :section_link do
    course
    linked_course { association :course, term: course.term }
    option_group { 0 }
    credit_hours { 0 }
  end
end
