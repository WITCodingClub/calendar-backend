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
# One leg of a WebAuthn ceremony. The API is stateless, so the challenge cannot
# live in a session: the client gets an opaque handle and sends it back with the
# authenticator's answer. Consuming a row deletes it, which is what makes a
# challenge single use.
class WebauthnChallenge < ApplicationRecord
  TTL = 5.minutes

  PURPOSES = %w[registration authentication].freeze

  belongs_to :user, optional: true

  validates :handle,    presence: true, uniqueness: true
  validates :challenge, presence: true
  validates :purpose,   presence: true, inclusion: { in: PURPOSES }
  validates :expires_at, presence: true

  scope :expired, -> { where(expires_at: ...Time.current) }

  def self.issue!(challenge:, purpose:, user: nil)
    expired.delete_all

    create!(
      handle:     SecureRandom.urlsafe_base64(32),
      challenge:  challenge,
      purpose:    purpose,
      user:       user,
      expires_at: TTL.from_now
    )
  end

  # Returns the challenge string and removes the row, so the same handle can
  # never be replayed. Returns nil for an unknown, expired, or mismatched row.
  def self.consume(handle:, purpose:)
    return nil if handle.blank?

    record = find_by(handle: handle, purpose: purpose)
    return nil if record.nil?

    record.destroy!
    return nil if record.expires_at <= Time.current

    record
  end
end
