# frozen_string_literal: true

FactoryBot.define do
  factory :passkey_handoff do
    association :user
    sequence(:code_digest) { |n| "factory-digest-#{n}" }
    purpose { "register" }
    expires_at { 2.minutes.from_now }
  end
end
