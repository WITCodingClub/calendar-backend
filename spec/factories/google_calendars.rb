# frozen_string_literal: true

FactoryBot.define do
  factory :google_calendar do
    association :oauth_credential
    sequence(:google_calendar_id) { |n| "factory-cal-#{n}" }
  end
end
