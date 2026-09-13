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
class Passkey < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :pky, min_hash_length: 12

  belongs_to :user

  validates :external_id, presence: true, uniqueness: true
  validates :public_key,  presence: true
  validates :nickname,    presence: true, length: { maximum: 60 },
                          uniqueness: { scope: :user_id, case_sensitive: false }

  scope :recently_used_first, -> { order(Arel.sql("last_used_at DESC NULLS LAST"), created_at: :desc) }

  # Removing a passkey is how someone reacts to losing the device holding it,
  # so the sessions it opened go with it. Otherwise the credential is gone but
  # whoever has the device stays signed in for up to ninety days.
  #
  # Before, not after: the sessions hold a foreign key to this row, so they have
  # to let go of it before it can be deleted.
  before_destroy :revoke_sessions_it_opened

  # Called once the assertion verifies. WebAuthn::Credential#verify rejects a
  # sign count that fails to advance, which is the documented signal that a
  # credential was cloned, so by this point the new count is known good.
  #
  # Note a platform authenticator reports zero every time — the counter is
  # optional and multi-device credentials do not keep one — so last_used_at is
  # the field that actually moves for most people.
  def record_use!(new_sign_count)
    update!(sign_count: new_sign_count, last_used_at: Time.current)
  end

  private

  def revoke_sessions_it_opened
    opened = UserSession.where(passkey_id: id)

    # rubocop:disable Rails/SkipsModelValidations
    opened.where(revoked_at: nil)
          .update_all(revoked_at: Time.current, revoked_reason: "passkey removed")
    # The row outlives the credential, so it keeps a readable history without
    # holding a key to something that no longer exists.
    opened.update_all(passkey_id: nil)
    # rubocop:enable Rails/SkipsModelValidations
  end
end
