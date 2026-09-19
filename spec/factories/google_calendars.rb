# frozen_string_literal: true

# == Schema Information
#
# Table name: google_calendars
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
#  index_google_calendars_on_google_calendar_id          (google_calendar_id) UNIQUE
#  index_google_calendars_on_last_synced_at              (last_synced_at)
#  index_google_calendars_on_oauth_credential_id_unique  (oauth_credential_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (oauth_credential_id => oauth_credentials.id)
#
FactoryBot.define do
  factory :google_calendar do
    association :oauth_credential
    sequence(:google_calendar_id) { |n| "factory-cal-#{n}" }
  end
end
