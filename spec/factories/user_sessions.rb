# frozen_string_literal: true

FactoryBot.define do
  factory :user_session do
    association :user
    sequence(:jti) { |n| "factory-session-jti-#{n}" }
    source { "google_onboard" }
    expires_at { 90.days.from_now }
  end
end
