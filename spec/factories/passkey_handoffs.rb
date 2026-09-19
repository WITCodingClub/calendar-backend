# frozen_string_literal: true

# == Schema Information
#
# Table name: passkey_handoffs
#
#  id          :bigint           not null, primary key
#  code_digest :string           not null
#  expires_at  :datetime         not null
#  purpose     :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  user_id     :bigint           not null
#
# Indexes
#
#  index_passkey_handoffs_on_code_digest  (code_digest) UNIQUE
#  index_passkey_handoffs_on_expires_at   (expires_at)
#  index_passkey_handoffs_on_user_id      (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :passkey_handoff do
    association :user
    sequence(:code_digest) { |n| "factory-digest-#{n}" }
    purpose { "register" }
    expires_at { 2.minutes.from_now }
  end
end
