# frozen_string_literal: true

FactoryBot.define do
  factory :webauthn_challenge do
    sequence(:handle) { |n| "factory-handle-#{n}" }
    challenge { "factory-challenge" }
    purpose { "authentication" }
    expires_at { 5.minutes.from_now }
  end
end
