# frozen_string_literal: true

# == Schema Information
#
# Table name: google_calendars
# Database name: primary
#
#  id                  :bigint           not null, primary key
#  description         :text
#  last_synced_at      :datetime
#  summary             :string
#  time_zone           :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  google_calendar_id  :string           not null
#  oauth_credential_id :bigint           not null
#
# Indexes
#
#  index_google_calendars_on_google_calendar_id   (google_calendar_id) UNIQUE
#  index_google_calendars_on_oauth_credential_id  (oauth_credential_id)
#
# Foreign Keys
#
#  fk_rails_...  (oauth_credential_id => oauth_credentials.id)
#
FactoryBot.define do
  factory :google_calendar do
    oauth_credential
    sequence(:google_calendar_id) { |n| "calendar_#{n}@group.calendar.google.com" }
    summary { "My Calendar" }
    description { "A test calendar" }
    time_zone { "America/Chicago" }
    last_synced_at { 1.hour.ago }

    trait :never_synced do
      last_synced_at { nil }
    end

    trait :stale do
      last_synced_at { 2.hours.ago }
    end
  end
end
