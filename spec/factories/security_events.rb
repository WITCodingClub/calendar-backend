# frozen_string_literal: true

# == Schema Information
#
# Table name: security_events
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
    sequence(:jti) { |n| "factory-jti-#{n}" }
    event_type { SecurityEvent::VERIFICATION }
    google_subject { "factory-subject" }

    trait :processed do
      processed { true }
      processed_at { Time.current }
    end
  end
end
