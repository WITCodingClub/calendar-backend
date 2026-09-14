# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "factory.user#{n}@wit.edu" }
    password { "password123" }
    password_confirmation { "password123" }
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
  end
end
