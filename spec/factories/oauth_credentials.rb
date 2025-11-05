# frozen_string_literal: true

# == Schema Information
#
# Table name: oauth_credentials
# Database name: primary
#
#  id               :bigint           not null, primary key
#  access_token     :string           not null
#  email            :string
#  metadata         :jsonb
#  provider         :string           not null
#  refresh_token    :string
#  token_expires_at :datetime
#  uid              :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  user_id          :bigint           not null
#
# Indexes
#
#  index_oauth_credentials_on_provider_and_uid     (provider,uid) UNIQUE
#  index_oauth_credentials_on_user_id              (user_id)
#  index_oauth_credentials_on_user_provider_email  (user_id,provider,email) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :oauth_credential do
    user
    provider { "google" }
    sequence(:uid) { |n| "google_user_#{n}" }
    sequence(:email) { |n| "user#{n}@example.com" }
    access_token { SecureRandom.hex(32) }
    refresh_token { SecureRandom.hex(32) }
    token_expires_at { 1.hour.from_now }
    metadata { {} }

    trait :with_course_calendar do
      metadata { { "course_calendar_id" => "calendar_#{SecureRandom.hex(8)}" } }
    end

    trait :expired do
      token_expires_at { 1.hour.ago }
    end
  end
end
