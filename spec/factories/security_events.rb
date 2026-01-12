# frozen_string_literal: true

# == Schema Information
#
# Table name: security_events
# Database name: primary
#
#  id                  :bigint           not null, primary key
#  event_type          :string           not null
#  expires_at          :datetime
#  google_subject      :string           not null
#  jti                 :string           not null
#  processed           :boolean          default(FALSE), not null
#  processed_at        :datetime
#  processing_error    :text
#  raw_event_data      :text
#  reason              :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  oauth_credential_id :bigint
#  user_id             :bigint
#
# Indexes
#
#  index_security_events_on_event_type           (event_type)
#  index_security_events_on_expires_at           (expires_at)
#  index_security_events_on_jti                  (jti) UNIQUE
#  index_security_events_on_oauth_credential_id  (oauth_credential_id)
#  index_security_events_on_processed            (processed)
#  index_security_events_on_user_id              (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (oauth_credential_id => oauth_credentials.id)
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :security_event do
    sequence(:jti) { |n| "unique-jti-#{n}-#{SecureRandom.hex(8)}" }
    event_type { SecurityEvent::SESSIONS_REVOKED }
    sequence(:google_subject) { |n| "google-sub-#{n}" }
    reason { nil }
    raw_event_data { '{"test": "data"}' }
    processed { false }
    processed_at { nil }
    processing_error { nil }

    # Associations
    user { nil }
    oauth_credential { nil }

    trait :sessions_revoked do
      event_type { SecurityEvent::SESSIONS_REVOKED }
    end

    trait :tokens_revoked do
      event_type { SecurityEvent::TOKENS_REVOKED }
    end

    trait :token_revoked do
      event_type { SecurityEvent::TOKEN_REVOKED }
    end

    trait :account_disabled do
      event_type { SecurityEvent::ACCOUNT_DISABLED }
    end

    trait :account_enabled do
      event_type { SecurityEvent::ACCOUNT_ENABLED }
    end

    trait :credential_change_required do
      event_type { SecurityEvent::ACCOUNT_CREDENTIAL_CHANGE_REQUIRED }
    end

    trait :verification do
      event_type { SecurityEvent::VERIFICATION }
      raw_event_data { '{"state": "test-verification"}' }
    end

    trait :hijacking do
      reason { "hijacking" }
    end

    trait :bulk_account do
      reason { "bulk-account" }
    end

    trait :processed do
      processed { true }
      processed_at { Time.current }
    end

    trait :with_error do
      processed { true }
      processed_at { Time.current }
      processing_error { "An error occurred during processing" }
    end

    trait :with_user do
      user
      google_subject { user.oauth_credentials.first&.uid || "google-sub-#{rand(1000)}" }
    end

    trait :with_oauth_credential do
      oauth_credential
      user { oauth_credential.user }
      google_subject { oauth_credential.uid }
    end
  end
end
