# frozen_string_literal: true

FactoryBot.define do
  factory :university_calendar_event do
    sequence(:ics_uid) { |n| "factory-ics-#{n}@calendar" }
    summary { "Factory University Event" }
    start_time { Time.zone.local(2026, 9, 1, 9, 0) }
    end_time { Time.zone.local(2026, 9, 1, 10, 0) }
  end
end
