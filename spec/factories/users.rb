# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "factory.user#{n}@wit.edu" }
    password { "password123" }
    password_confirmation { "password123" }
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
    # User is :confirmable, and an unconfirmed user cannot sign in.
    confirmed_at { Time.current }

    trait :unconfirmed do
      confirmed_at { nil }
    end
  end
end
