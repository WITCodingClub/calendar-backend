# frozen_string_literal: true

# Carries authority between the extension and the passkey page, in one direction
# at a time.
#
# The ceremony runs on this site, not in the extension, so the two halves of a
# passkey flow sit in different places and have to pass something between them:
#
#   register — the extension holds a JWT and the page does not. It mints a
#              handoff and puts it in the page's URL, and the page spends it to
#              register a passkey for that account.
#   session  — the page finishes an assertion and the extension needs the JWT.
#              The page redirects back with a handoff rather than the token
#              itself, so no session lands in a URL, in browser history, or in a
#              referer header.
#
# A handoff is a bearer credential, so it is single use, expires in two minutes,
# and is stored only as a digest.
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
class PasskeyHandoff < ApplicationRecord
  TTL = 2.minutes

  PURPOSES = %w[register session].freeze

  belongs_to :user

  validates :code_digest, presence: true, uniqueness: true
  validates :purpose,     presence: true, inclusion: { in: PURPOSES }
  validates :expires_at,  presence: true

  scope :expired, -> { where(expires_at: ...Time.current) }

  # Returns the raw code. It is never recoverable afterwards.
  def self.issue!(user:, purpose:)
    expired.delete_all

    code = SecureRandom.urlsafe_base64(32)
    create!(
      user:        user,
      code_digest: digest(code),
      purpose:     purpose,
      expires_at:  TTL.from_now
    )
    code
  end

  # Returns the user without spending the code. A registration takes two calls
  # and both must be authenticated, so the code has to survive the first one.
  def self.peek(code:, purpose:)
    return nil if code.blank?

    record = find_by(code_digest: digest(code), purpose: purpose)
    return nil if record.nil? || record.expires_at <= Time.current

    record.user
  end

  # Spends a code and returns its user, or nil for anything unknown, expired, or
  # minted for the other direction.
  def self.consume(code:, purpose:)
    return nil if code.blank?

    record = find_by(code_digest: digest(code), purpose: purpose)
    return nil if record.nil?

    record.destroy!
    return nil if record.expires_at <= Time.current

    record.user
  end

  def self.digest(code)
    Digest::SHA256.hexdigest(code.to_s)
  end
end
