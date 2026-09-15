# frozen_string_literal: true

# An outside account that can sign a person in to the dashboard. Today the only
# provider is Microsoft (see MicrosoftSignIn).
#
# This is not an OauthCredential. A credential holds tokens for calendar sync,
# and the calendar code acts on every credential it finds. An identity holds no
# tokens, so nothing can sync through it by mistake.
#
# Removing an identity ends no session. The person may have signed in with
# Google or a passkey, and those sessions are not this record's to end.
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
class SignInIdentity < ApplicationRecord
  PROVIDERS = %w[microsoft].freeze

  belongs_to :user

  validates :provider,  presence: true, inclusion: { in: PROVIDERS }
  validates :tenant_id, presence: true
  validates :uid,       presence: true, uniqueness: { scope: [ :provider, :tenant_id ] }
  validates :email,     presence: true

  scope :microsoft, -> { where(provider: "microsoft") }

  def record_sign_in!(email:)
    update!(email: email, last_signed_in_at: Time.current)
  end
end
