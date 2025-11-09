# frozen_string_literal: true

# Service for handling Google RISC security events
# Takes appropriate security actions based on event type
class RiscEventHandlerService
  attr_reader :event_data, :security_event

  def initialize(event_data)
    @event_data = event_data
    @security_event = nil
  end

  # Process the event and take appropriate action
  def process
    # Find the user by Google subject (sub claim)
    user = find_user_by_google_subject(event_data[:google_subject])

    # Create the SecurityEvent record
    @security_event = create_security_event(user)

    # Handle verification events (test events)
    if event_data[:event_type] == SecurityEvent::VERIFICATION
      handle_verification_event
      return { success: true, action: "verification_logged" }
    end

    # If we can't find the user, log but don't fail
    unless user
      Rails.logger.warn("RISC event received for unknown user: #{event_data[:google_subject]}")
      @security_event.mark_processed!(error: "User not found")
      return { success: true, action: "user_not_found" }
    end

    # Handle the event based on type
    result = case event_data[:event_type]
    when SecurityEvent::SESSIONS_REVOKED
      handle_sessions_revoked(user)
    when SecurityEvent::TOKENS_REVOKED
      handle_tokens_revoked(user)
    when SecurityEvent::TOKEN_REVOKED
      handle_token_revoked(user)
    when SecurityEvent::ACCOUNT_DISABLED
      handle_account_disabled(user)
    when SecurityEvent::ACCOUNT_ENABLED
      handle_account_enabled(user)
    when SecurityEvent::ACCOUNT_CREDENTIAL_CHANGE_REQUIRED
      handle_credential_change_required(user)
    else
      Rails.logger.warn("Unknown RISC event type: #{event_data[:event_type]}")
      { action: "unknown_event_type" }
    end

    # Mark the event as processed
    @security_event.mark_processed!

    { success: true, **result }
  rescue => e
    Rails.logger.error("Error processing RISC event: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))

    @security_event&.mark_processed!(error: e.message)

    { success: false, error: e.message }
  end

  private

  # Find user by Google subject ID (sub claim)
  def find_user_by_google_subject(google_subject)
    # Find OAuth credential with this UID
    oauth_credential = OauthCredential.find_by(provider: "google", uid: google_subject)
    oauth_credential&.user
  end

  # Create SecurityEvent record
  def create_security_event(user)
    oauth_credential = user&.oauth_credentials&.find_by(provider: "google", uid: event_data[:google_subject])

    SecurityEvent.create!(
      jti: event_data[:jti],
      event_type: event_data[:event_type],
      google_subject: event_data[:google_subject],
      user: user,
      oauth_credential: oauth_credential,
      reason: event_data[:reason],
      raw_event_data: event_data[:raw_event_data]
    )
  end

  # Handle sessions-revoked event
  # Required: End all currently open sessions
  def handle_sessions_revoked(user)
    Rails.logger.info("RISC: Sessions revoked for user #{user.id}")

    # Note: Rails default cookie-based sessions can't be centrally revoked
    # Best we can do is destroy OAuth credentials which will prevent calendar sync
    revoke_all_oauth_credentials(user)

    { action: "sessions_revoked", oauth_credentials_revoked: true }
  end

  # Handle tokens-revoked event
  # Required: If for Google Sign-in, terminate sessions
  # Suggested: Delete stored OAuth tokens
  def handle_tokens_revoked(user)
    Rails.logger.info("RISC: OAuth tokens revoked for user #{user.id}")

    revoke_all_oauth_credentials(user)

    { action: "tokens_revoked", oauth_credentials_revoked: true }
  end

  # Handle token-revoked event (single token)
  # Required: Delete the specific refresh token if stored
  def handle_token_revoked(user)
    Rails.logger.info("RISC: Specific OAuth token revoked for user #{user.id}")

    # For single token revocation, we'd need to match the token
    # Since we encrypt tokens, we can't easily search them
    # Safest approach is to revoke all Google OAuth credentials
    revoke_all_oauth_credentials(user)

    { action: "token_revoked", oauth_credentials_revoked: true }
  end

  # Handle account-disabled event
  # Required (if hijacking): End all currently open sessions
  # Suggested: Disable Google Sign-in and email recovery
  def handle_account_disabled(user)
    Rails.logger.info("RISC: Account disabled for user #{user.id}, reason: #{event_data[:reason]}")

    # If account was hijacked, take immediate action
    if event_data[:reason] == "hijacking"
      revoke_all_oauth_credentials(user)
      { action: "account_disabled_hijacking", oauth_credentials_revoked: true }
    else
      # For other reasons, just log and monitor
      { action: "account_disabled", reason: event_data[:reason] }
    end
  end

  # Handle account-enabled event
  # Suggested: Re-enable Google Sign-in
  def handle_account_enabled(user)
    Rails.logger.info("RISC: Account enabled for user #{user.id}")

    # Nothing to do - user can re-authenticate normally
    { action: "account_enabled" }
  end

  # Handle credential-change-required event
  # Suggested: Watch for suspicious activity
  def handle_credential_change_required(user)
    Rails.logger.info("RISC: Credential change required for user #{user.id}")

    # Log for monitoring, but don't take automatic action
    { action: "credential_change_required" }
  end

  # Handle verification event (test event)
  def handle_verification_event
    Rails.logger.info("RISC: Verification event received, state: #{event_data[:state]}")

    @security_event.mark_processed!

    { action: "verification", state: event_data[:state] }
  end

  # Revoke all Google OAuth credentials for a user
  def revoke_all_oauth_credentials(user)
    user.oauth_credentials.google.each do |credential|
      begin
        # The before_destroy callback will handle calendar access revocation
        credential.destroy!
        Rails.logger.info("Revoked OAuth credential #{credential.id} for user #{user.id}")
      rescue => e
        Rails.logger.error("Failed to revoke OAuth credential #{credential.id}: #{e.message}")
      end
    end
  end
end
