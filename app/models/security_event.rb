# frozen_string_literal: true

class SecurityEvent < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :sev, min_hash_length: 12

  belongs_to :user, optional: true
  belongs_to :oauth_credential, optional: true

  validates :jti, presence: true, uniqueness: true
  validates :event_type, presence: true
  validates :google_subject, presence: true

  SESSIONS_REVOKED                   = "https://schemas.openid.net/secevent/risc/event-type/sessions-revoked"
  TOKENS_REVOKED                     = "https://schemas.openid.net/secevent/oauth/event-type/tokens-revoked"
  TOKEN_REVOKED                      = "https://schemas.openid.net/secevent/oauth/event-type/token-revoked"
  ACCOUNT_DISABLED                   = "https://schemas.openid.net/secevent/risc/event-type/account-disabled"
  ACCOUNT_ENABLED                    = "https://schemas.openid.net/secevent/risc/event-type/account-enabled"
  ACCOUNT_CREDENTIAL_CHANGE_REQUIRED = "https://schemas.openid.net/secevent/risc/event-type/account-credential-change-required"
  VERIFICATION                       = "https://schemas.openid.net/secevent/risc/event-type/verification"

  ALL_EVENT_TYPES = [
    SESSIONS_REVOKED, TOKENS_REVOKED, TOKEN_REVOKED,
    ACCOUNT_DISABLED, ACCOUNT_ENABLED, ACCOUNT_CREDENTIAL_CHANGE_REQUIRED, VERIFICATION
  ].freeze

  RETENTION_DAYS = 90

  scope :unprocessed,   -> { where(processed: false) }
  scope :processed,     -> { where(processed: true) }
  scope :by_event_type, ->(type) { where(event_type: type) }
  scope :for_user,      ->(user) { where(user: user) }
  scope :expired,       -> { where(expires_at: ...Time.current) }
  scope :recent,        -> { order(created_at: :desc) }

  before_create :set_expiration

  def mark_processed!(error: nil)
    update!(processed: true, processed_at: Time.current, processing_error: error)
  end

  def requires_immediate_action?
    event_type.in?([ SESSIONS_REVOKED, ACCOUNT_DISABLED ]) && reason == "hijacking"
  end

  def event_type_name
    event_type.split("/").last
  end

  def verification_event?
    event_type == VERIFICATION
  end

  private

  def set_expiration
    self.expires_at ||= RETENTION_DAYS.days.from_now
  end
end
