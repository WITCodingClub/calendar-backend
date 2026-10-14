# frozen_string_literal: true

FactoryBot.define do
  factory :catalog_course do
    subject_code { "COMP" }
    sequence(:course_number) { |n| 5000 + n }
    title { Faker::Educator.course_name }

    trait :with_details do
      description { Faker::Lorem.paragraph }
      credit_hours { 4 }
      typically_offered { %w[fall spring] }
      details_fetched_at { Time.current }
    end
  end
end
