# frozen_string_literal: true

FactoryBot.define do
  factory :enrollment do
    association :user
    association :course
    term { course.term }
  end
end
