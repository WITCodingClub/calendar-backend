# frozen_string_literal: true

FactoryBot.define do
  factory :enrollment_snapshot do
    association :user
    association :term
    sequence(:crn) { |n| 70_000 + n }
  end
end
