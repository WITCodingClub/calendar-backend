# frozen_string_literal: true

FactoryBot.define do
  factory :final_exam do
    association :term
    sequence(:crn) { |n| 90_000 + n }
    exam_date { Date.new(2026, 12, 17) }
    start_time { 800 }
    end_time { 1000 }
  end
end
