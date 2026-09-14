# frozen_string_literal: true

FactoryBot.define do
  factory :related_professor do
    association :faculty
    sequence(:rmp_id) { |n| "factory-related-rmp-#{n}" }
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
  end
end
