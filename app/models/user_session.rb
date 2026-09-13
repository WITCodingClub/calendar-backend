# frozen_string_literal: true

# One issued API token, so that it can be taken away again.
#
# A JWT on its own cannot be revoked: it is valid until it expires, and the only
# lever is rotating the signing secret, which signs out everybody at once. Every
# token now carries a jti and a row here, and authentication checks the row — so
# a lost laptop costs one revocation instead of a ninety-day wait.
# == Schema Information
#
# Table name: user_sessions
#
#  id             :bigint           not null, primary key
#  device_label   :string
#  expires_at     :datetime         not null
#  ip_address     :string
#  jti            :string           not null
#  last_seen_at   :datetime
#  revoked_at     :datetime
#  revoked_reason :string
#  source         :string           not null
#  user_agent     :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  passkey_id     :bigint
#  user_id        :bigint           not null
#
# Indexes
#
#  index_user_sessions_on_expires_at              (expires_at)
#  index_user_sessions_on_jti                     (jti) UNIQUE
#  index_user_sessions_on_passkey_id              (passkey_id)
#  index_user_sessions_on_user_id                 (user_id)
#  index_user_sessions_on_user_id_and_revoked_at  (user_id,revoked_at)
#
# Foreign Keys
#
#  fk_rails_...  (passkey_id => passkeys.id)
#  fk_rails_...  (user_id => users.id)
#
class UserSession < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :ses, min_hash_length: 12

  # How the session came to exist. Worth recording: "sign out my old phone" is
  # hard to act on without knowing which session is which.
  SOURCES = %w[google_onboard passkey].freeze

  # Writing last_seen_at on every request would double the writes on an API the
  # extension already calls often, and nobody needs minute-accurate presence.
  LAST_SEEN_RESOLUTION = 5.minutes

  belongs_to :user
  belongs_to :passkey, optional: true

  validates :jti,        presence: true, uniqueness: true
  validates :source,     presence: true, inclusion: { in: SOURCES }
  validates :expires_at, presence: true

  scope :active,  -> { where(revoked_at: nil).where(expires_at: Time.current..) }
  scope :revoked, -> { where.not(revoked_at: nil) }
  scope :recent_first, -> { order(Arel.sql("last_seen_at DESC NULLS LAST"), created_at: :desc) }

  def active?
    revoked_at.nil? && expires_at > Time.current
  end

  def revoked?
    revoked_at.present?
  end

  def revoke!(reason: "signed out")
    return if revoked?

    update!(revoked_at: Time.current, revoked_reason: reason)
  end

  def touch_last_seen!
    return if last_seen_at.present? && last_seen_at > LAST_SEEN_RESOLUTION.ago

    update_column(:last_seen_at, Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  # Ends every session for a user. Called when something happens that should
  # invalidate anything already issued — a removed passkey, a disconnected
  # Google account, a changed password.
  def self.revoke_all_for(user, reason:, except: nil)
    scope = where(user_id: user.id, revoked_at: nil)
    scope = scope.where.not(id: except.id) if except

    scope.update_all(revoked_at: Time.current, revoked_reason: reason) # rubocop:disable Rails/SkipsModelValidations
  end

  # A coarse, honest label. Parsing user agents precisely is a losing game, and
  # the point is only to help someone recognise their own device in a list.
  def self.label_for(user_agent)
    ua = user_agent.to_s

    browser =
      if    ua.include?("Firefox")                        then "Firefox"
      elsif ua.include?("Edg/")                           then "Edge"
      elsif ua.include?("Chrome") || ua.include?("CriOS") then "Chrome"
      elsif ua.include?("Safari")                         then "Safari"
      end

    platform =
      if    ua.include?("Windows")                     then "Windows"
      elsif ua.include?("Android")                     then "Android"
      elsif ua.include?("iPhone") || ua.include?("iPad") then "iOS"
      elsif ua.include?("Mac OS X") || ua.include?("Macintosh") then "macOS"
      elsif ua.include?("Linux")                       then "Linux"
      end

    [ browser, platform ].compact.join(" on ").presence || "Unknown device"
  end
end
