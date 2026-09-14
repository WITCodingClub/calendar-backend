# frozen_string_literal: true

FactoryBot.define do
  factory :oauth_credential do
    association :user
    provider { "google" }
    sequence(:uid) { |n| "factory-google-uid-#{n}" }
    email { user.email }
    access_token { "factory-access-token" }
  end
end
