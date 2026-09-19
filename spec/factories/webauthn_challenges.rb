# frozen_string_literal: true

# == Schema Information
#
# Table name: webauthn_challenges
#
#  id         :bigint           not null, primary key
#  challenge  :string           not null
#  expires_at :datetime         not null
#  handle     :string           not null
#  purpose    :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint
#
# Indexes
#
#  index_webauthn_challenges_on_expires_at  (expires_at)
#  index_webauthn_challenges_on_handle      (handle) UNIQUE
#  index_webauthn_challenges_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :webauthn_challenge do
    sequence(:handle) { |n| "factory-handle-#{n}" }
    challenge { "factory-challenge" }
    purpose { "authentication" }
    expires_at { 5.minutes.from_now }
  end
end
