# frozen_string_literal: true

FactoryBot.define do
  factory :oauth_credential do
    association :user
    provider { "google" }
    sequence(:uid) { |n| "factory-google-uid-#{n}" }
    email { user.email }
    access_token { "factory-access-token" }

    trait :microsoft do
      provider { "microsoft" }
      sequence(:uid) { |n| "factory-microsoft-oid-#{n}" }
      refresh_token { Faker::Alphanumeric.alphanumeric(number: 32) }
      token_expires_at { 1.hour.from_now }
    end
  end
end
