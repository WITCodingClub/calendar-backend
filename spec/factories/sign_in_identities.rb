# frozen_string_literal: true

# == Schema Information
#
# Table name: sign_in_identities
#
#  id                :bigint           not null, primary key
#  email             :string           not null
#  last_signed_in_at :datetime
#  provider          :string           not null
#  uid               :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  tenant_id         :string           not null
#  user_id           :bigint           not null
#
# Indexes
#
#  index_sign_in_identities_on_provider_and_tenant_id_and_uid  (provider,tenant_id,uid) UNIQUE
#  index_sign_in_identities_on_user_id                         (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :sign_in_identity do
    association :user
    provider { "microsoft" }
    tenant_id { Faker::Internet.uuid }
    sequence(:uid) { |n| "factory-microsoft-oid-#{n}" }
    email { user.email }
  end
end
