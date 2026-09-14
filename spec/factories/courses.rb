# frozen_string_literal: true

FactoryBot.define do
  factory :course do
    association :term
    sequence(:crn) { |n| 10_000 + n }
    subject { "COMP" }
    sequence(:course_number) { |n| 1000 + n }
    section_number { "01" }
    schedule_type { :lecture }
    title { Faker::Educator.course_name }
    start_date { Date.new(2026, 9, 8) }
    end_date { Date.new(2026, 12, 15) }
  end
end
