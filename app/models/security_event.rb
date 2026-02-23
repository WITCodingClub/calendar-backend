# frozen_string_literal: true

# == Schema Information
#
# Table name: security_events
# Database name: primary
#
#  id                  :bigint           not null, primary key
#  event_type          :string           not null
#  expires_at          :datetime
#  google_subject      :string           not null
#  jti                 :string           not null
#  processed           :boolean          default(FALSE), not null
#  processed_at        :datetime
#  processing_error    :text
#  raw_event_data      :text
#  reason              :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  oauth_credential_id :bigint
#  user_id             :bigint
#
# Indexes
#
#  index_security_events_on_event_type           (event_type)
#  index_security_events_on_expires_at           (expires_at)
#  index_security_events_on_jti                  (jti) UNIQUE
#  index_security_events_on_oauth_credential_id  (oauth_credential_id)
#  index_security_events_on_processed            (processed)
#  index_security_events_on_user_id              (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (oauth_credential_id => oauth_credentials.id)
#  fk_rails_...  (user_id => users.id)
#
class SecurityEvent < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :sev, min_hash_length: 12

  belongs_to :user, optional: true
  belongs_to :oauth_credential, optional: true

  validates :jti, presence: true, uniqueness: true
  validates :event_type, presence: true
  validates :google_subject, presence: true

  encrypts :raw_event_data

  # Event types constants
  SESSIONS_REVOKED = "https://schemas.openid.net/secevent/risc/event-type/sessions-revoked"
  TOKENS_REVOKED = "https://schemas.openid.net/secevent/oauth/event-type/tokens-revoked"
  TOKEN_REVOKED = "https://schemas.openid.net/secevent/oauth/event-type/token-revoked"
  ACCOUNT_DISABLED = "https://schemas.openid.net/secevent/risc/event-type/account-disabled"
  ACCOUNT_ENABLED = "https://schemas.openid.net/secevent/risc/event-type/account-enabled"
  ACCOUNT_CREDENTIAL_CHANGE_REQUIRED = "https://schemas.openid.net/secevent/risc/event-type/account-credential-change-required"
  VERIFICATION = "https://schemas.openid.net/secevent/risc/event-type/verification"

  ALL_EVENT_TYPES = [
    SESSIONS_REVOKED,
    TOKENS_REVOKED,
    TOKEN_REVOKED,
    ACCOUNT_DISABLED,
    ACCOUNT_ENABLED,
    ACCOUNT_CREDENTIAL_CHANGE_REQUIRED,
    VERIFICATION
  ].freeze

  # Retention policy: delete events after 90 days (per RISC TOS)
  RETENTION_DAYS = 90

  # Scopes
  scope :unprocessed, -> { where(processed: false) }
  scope :processed, -> { where(processed: true) }
  scope :by_event_type, ->(type) { where(event_type: type) }
  scope :for_user, ->(user) { where(user: user) }
  scope :expired, -> { where(expires_at: ...Time.current) }
  scope :recent, -> { order(created_at: :desc) }

  # Set expiration date before creation
  before_create :set_expiration

  # Mark as processed
  def mark_processed!(error: nil)
    update!(
      processed: true,
      processed_at: Time.current,
      processing_error: error
    )
  end

  # Check if event requires immediate action
  def requires_immediate_action?
    event_type.in?([SESSIONS_REVOKED, ACCOUNT_DISABLED]) && reason == "hijacking"
  end

  # Get the event type name (last part of URI)
  def event_type_name
    event_type.split("/").last
  end

  # Check if this is a verification event
  def verification_event?
    event_type == VERIFICATION
  end

  private

  def set_expiration
    self.expires_at ||= RETENTION_DAYS.days.from_now
  end

end
