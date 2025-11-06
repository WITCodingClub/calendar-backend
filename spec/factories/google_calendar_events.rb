# frozen_string_literal: true

# == Schema Information
#
# Table name: google_calendar_events
# Database name: primary
#
#  id                 :bigint           not null, primary key
#  end_time           :datetime
#  event_data_hash    :string
#  last_synced_at     :datetime
#  location           :string
#  recurrence         :text
#  start_time         :datetime
#  summary            :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  google_calendar_id :bigint           not null
#  google_event_id    :string           not null
#  meeting_time_id    :bigint
#  user_id            :bigint           not null
#
# Indexes
#
#  index_google_calendar_events_on_google_calendar_id               (google_calendar_id)
#  index_google_calendar_events_on_google_calendar_id_and_meeting_  (google_calendar_id,meeting_time_id)
#  index_google_calendar_events_on_google_event_id                  (google_event_id)
#  index_google_calendar_events_on_meeting_time_id                  (meeting_time_id)
#  index_google_calendar_events_on_user_id                          (user_id)
#  index_google_calendar_events_on_user_id_and_meeting_time_id      (user_id,meeting_time_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (meeting_time_id => meeting_times.id)
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :google_calendar_event do
    user
    google_calendar
    meeting_time { nil }
    sequence(:google_event_id) { |n| "event_#{n}_#{SecureRandom.hex(8)}" }
    summary { "Course Title" }
    location { "Building - Room 101" }
    start_time { Time.zone.parse("2025-01-15 09:00:00") }
    end_time { Time.zone.parse("2025-01-15 10:30:00") }
    recurrence { ["RRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20250515T235959Z"] }
    event_data_hash {
      GoogleCalendarEvent.generate_data_hash({
                                               summary: summary,
                                               location: location,
                                               start_time: start_time,
                                               end_time: end_time,
                                               recurrence: recurrence
                                             })
    }
    last_synced_at { 1.hour.ago }

    trait :never_synced do
      last_synced_at { nil }
    end

    trait :stale do
      last_synced_at { 2.hours.ago }
    end
  end
end
