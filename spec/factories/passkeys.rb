# frozen_string_literal: true

# == Schema Information
#
# Table name: passkeys
#
#  id           :bigint           not null, primary key
#  last_used_at :datetime
#  nickname     :string           not null
#  public_key   :string           not null
#  sign_count   :bigint           default(0), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  external_id  :string           not null
#  user_id      :bigint           not null
#
# Indexes
#
#  index_passkeys_on_external_id           (external_id) UNIQUE
#  index_passkeys_on_user_id               (user_id)
#  index_passkeys_on_user_id_and_nickname  (user_id,nickname) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :passkey do
    association :user
    sequence(:external_id) { |n| "factory-ext-id-#{n}" }
    sequence(:nickname) { |n| "Factory Passkey #{n}" }
    public_key { "factory-public-key" }
  end
end
