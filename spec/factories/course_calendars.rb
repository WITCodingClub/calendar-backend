# frozen_string_literal: true

# == Schema Information
#
# Table name: calendars
#
#  id                   :bigint           not null, primary key
#  description          :text
#  last_synced_at       :datetime
#  provider             :string           default("google"), not null
#  summary              :string
#  time_zone            :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  external_calendar_id :string           not null
#  oauth_credential_id  :bigint           not null
#
# Indexes
#
#  index_calendars_on_last_synced_at                        (last_synced_at)
#  index_calendars_on_oauth_credential_id_unique            (oauth_credential_id) UNIQUE
#  index_calendars_on_provider_and_external_calendar_id     (provider,external_calendar_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (oauth_credential_id => oauth_credentials.id)
#
FactoryBot.define do
  factory :course_calendar do
    association :oauth_credential
    sequence(:external_calendar_id) { |n| "factory-cal-#{n}" }

    trait :microsoft do
      provider { "microsoft" }
      association :oauth_credential, :microsoft
      sequence(:external_calendar_id) { |n| "AAMkFactoryCalendar#{n}" }
    end

    # The person's own main Microsoft calendar, which the app never deletes.
    trait :primary do
      microsoft
      placement { "primary" }
    end
  end
end
