# frozen_string_literal: true

class RiscEventHandlerService
  attr_reader :event_data, :security_event

  def initialize(event_data)
    @event_data = event_data
    @security_event = nil
  end

  def process
    user = find_user_by_google_subject(event_data[:google_subject])
    @security_event = create_security_event(user)

    if event_data[:event_type] == SecurityEvent::VERIFICATION
      handle_verification_event
      return { success: true, action: "verification_logged" }
    end

    unless user
      Rails.logger.warn("RISC event received for unknown user: #{event_data[:google_subject]}")
      @security_event.mark_processed!(error: "User not found")
      return { success: true, action: "user_not_found" }
    end

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

    @security_event.mark_processed!

    { success: true, **result }
  rescue => e
    Rails.logger.error("Error processing RISC event: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))

    @security_event&.mark_processed!(error: e.message)

    { success: false, error: e.message }
  end

  private

  def find_user_by_google_subject(google_subject)
    oauth_credential = OauthCredential.find_by(provider: "google", uid: google_subject)
    oauth_credential&.user
  end

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

  def handle_sessions_revoked(user)
    Rails.logger.info("RISC: Sessions revoked for user #{user.id}")
    revoke_all_oauth_credentials(user)
    { action: "sessions_revoked", oauth_credentials_revoked: true }
  end

  def handle_tokens_revoked(user)
    Rails.logger.info("RISC: OAuth tokens revoked for user #{user.id}")
    revoke_all_oauth_credentials(user)
    { action: "tokens_revoked", oauth_credentials_revoked: true }
  end

  def handle_token_revoked(user)
    Rails.logger.info("RISC: Specific OAuth token revoked for user #{user.id}")
    revoke_all_oauth_credentials(user)
    { action: "token_revoked", oauth_credentials_revoked: true }
  end

  def handle_account_disabled(user)
    Rails.logger.info("RISC: Account disabled for user #{user.id}, reason: #{event_data[:reason]}")

    if event_data[:reason] == "hijacking"
      revoke_all_oauth_credentials(user)
      { action: "account_disabled_hijacking", oauth_credentials_revoked: true }
    else
      { action: "account_disabled", reason: event_data[:reason] }
    end
  end

  def handle_account_enabled(user)
    Rails.logger.info("RISC: Account enabled for user #{user.id}")
    { action: "account_enabled" }
  end

  def handle_credential_change_required(user)
    Rails.logger.info("RISC: Credential change required for user #{user.id}")
    { action: "credential_change_required" }
  end

  def handle_verification_event
    Rails.logger.info("RISC: Verification event received, state: #{event_data[:state]}")
    @security_event.mark_processed!
    { action: "verification", state: event_data[:state] }
  end

  def revoke_all_oauth_credentials(user)
    user.oauth_credentials.google.each do |credential|
      credential.destroy!
      Rails.logger.info("Revoked OAuth credential #{credential.id} for user #{user.id}")
    rescue => e
      Rails.logger.error("Failed to revoke OAuth credential #{credential.id}: #{e.message}")
    end
  end
end
