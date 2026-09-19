# frozen_string_literal: true

# == Schema Information
#
# Table name: user_sessions
#
#  id             :bigint           not null, primary key
#  device_label   :string
#  expires_at     :datetime         not null
#  ip_address     :string
#  jti            :string           not null
#  last_seen_at   :datetime
#  revoked_at     :datetime
#  revoked_reason :string
#  source         :string           not null
#  user_agent     :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  passkey_id     :bigint
#  user_id        :bigint           not null
#
# Indexes
#
#  index_user_sessions_on_expires_at              (expires_at)
#  index_user_sessions_on_jti                     (jti) UNIQUE
#  index_user_sessions_on_passkey_id              (passkey_id)
#  index_user_sessions_on_user_id                 (user_id)
#  index_user_sessions_on_user_id_and_revoked_at  (user_id,revoked_at)
#
# Foreign Keys
#
#  fk_rails_...  (passkey_id => passkeys.id)
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :user_session do
    association :user
    sequence(:jti) { |n| "factory-session-jti-#{n}" }
    source { "google_onboard" }
    expires_at { 90.days.from_now }
  end
end
