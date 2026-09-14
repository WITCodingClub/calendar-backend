# frozen_string_literal: true

FactoryBot.define do
  factory :faculty do
    sequence(:email) { |n| "factory-faculty#{n}@wit.edu" }
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
  end
end
