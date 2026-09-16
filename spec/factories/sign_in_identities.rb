# frozen_string_literal: true

FactoryBot.define do
  factory :sign_in_identity do
    association :user
    provider { "microsoft" }
    tenant_id { Faker::Internet.uuid }
    sequence(:uid) { |n| "factory-microsoft-oid-#{n}" }
    email { user.email }
  end
end
