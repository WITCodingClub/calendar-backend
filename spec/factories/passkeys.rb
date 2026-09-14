# frozen_string_literal: true

FactoryBot.define do
  factory :passkey do
    association :user
    sequence(:external_id) { |n| "factory-ext-id-#{n}" }
    sequence(:nickname) { |n| "Factory Passkey #{n}" }
    public_key { "factory-public-key" }
  end
end
