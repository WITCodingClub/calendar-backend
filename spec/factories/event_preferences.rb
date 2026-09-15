# frozen_string_literal: true

FactoryBot.define do
  factory :event_preference do
    association :user
    association :preferenceable, factory: :course_meeting_time
    reminder_settings { [] }

    trait :for_calendar_event do
      association :preferenceable, factory: :calendar_event
    end
  end
end
