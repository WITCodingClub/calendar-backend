# frozen_string_literal: true

FactoryBot.define do
  factory :course_calendar do
    association :oauth_credential
    sequence(:external_calendar_id) { |n| "factory-cal-#{n}" }

    trait :microsoft do
      provider { "microsoft" }
      association :oauth_credential, :microsoft
      sequence(:external_calendar_id) { |n| "AAMkFactoryCalendar#{n}" }
    end
  end
end
