# frozen_string_literal: true

# == Schema Information
#
# Table name: oauth_credentials
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
#  index_oauth_credentials_on_token_expires_at     (token_expires_at)
#  index_oauth_credentials_on_user_id              (user_id)
#  index_oauth_credentials_on_user_provider_email  (user_id,provider,email) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :oauth_credential do
    association :user
    provider { "google" }
    sequence(:uid) { |n| "factory-google-uid-#{n}" }
    email { user.email }
    access_token { "factory-access-token" }

    trait :microsoft do
      provider { "microsoft" }
      sequence(:uid) { |n| "factory-microsoft-oid-#{n}" }
      refresh_token { Faker::Alphanumeric.alphanumeric(number: 32) }
      token_expires_at { 1.hour.from_now }
    end
  end
end
