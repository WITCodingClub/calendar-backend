# frozen_string_literal: true

module Risc
  class EventHandler
    # A credential could not be revoked. The event stays unprocessed, so the job
    # retries it and does not skip it as already seen.
    class RevocationFailed < StandardError; end

    # A database failure that a later attempt can clear. These reach the job, so
    # `retry_on` runs and the revoke event is not dropped.
    TRANSIENT_ERRORS = [
      ActiveRecord::ConnectionNotEstablished,
      ActiveRecord::QueryAborted, # statement timeout, cancelled query, lost connection
      ActiveRecord::LockWaitTimeout,
      ActiveRecord::TransactionRollbackError # deadlock, serialization failure
    ].freeze

    # The action of each event type that does not depend on the event, and
    # whether it revokes every Google credential of the person.
    ACTIONS = {
      SecurityEvent::SESSIONS_REVOKED                   => [ "sessions_revoked", true ],
      SecurityEvent::TOKENS_REVOKED                     => [ "tokens_revoked", true ],
      SecurityEvent::TOKEN_REVOKED                      => [ "token_revoked", true ],
      SecurityEvent::ACCOUNT_ENABLED                    => [ "account_enabled", false ],
      SecurityEvent::ACCOUNT_CREDENTIAL_CHANGE_REQUIRED => [ "credential_change_required", false ]
    }.freeze

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

      result = handle(user)
      @security_event.mark_processed!

      { success: true, **result }
    rescue *TRANSIENT_ERRORS => e
      Rails.logger.error("RISC event #{event_data[:jti]} left unprocessed: #{e.class}: #{e.message}")
      raise
    rescue RevocationFailed => e
      Rails.logger.error("RISC event #{event_data[:jti]} left unprocessed: #{e.message}")
      raise
    rescue => e
      Rails.error.report(e, handled: true, context: { jti: event_data[:jti] })

      @security_event&.mark_processed!(error: e.message)

      { success: false, error: e.message }
    end

    private

    def find_user_by_google_subject(google_subject)
      oauth_credential = OauthCredential.find_by(provider: "google", uid: google_subject)
      oauth_credential&.user
    end

    # A retry finds the row that the failed attempt left, instead of failing on
    # the unique jti.
    def create_security_event(user)
      oauth_credential = user&.oauth_credentials&.find_by(provider: "google", uid: event_data[:google_subject])

      SecurityEvent.find_or_initialize_by(jti: event_data[:jti]).tap do |event|
        event.update!(
          event_type: event_data[:event_type],
          google_subject: event_data[:google_subject],
          user: user,
          oauth_credential: oauth_credential,
          reason: event_data[:reason],
          raw_event_data: event_data[:raw_event_data]
        )
      end
    end

    def handle(user)
      event_type = event_data[:event_type]
      return handle_account_disabled(user) if event_type == SecurityEvent::ACCOUNT_DISABLED

      action, revoke = ACTIONS[event_type]
      unless action
        Rails.logger.warn("Unknown RISC event type: #{event_type}")
        return { action: "unknown_event_type" }
      end

      Rails.logger.info("RISC: #{action} for user #{user.id}")
      return { action: action } unless revoke

      revoke_all_oauth_credentials(user)
      { action: action, oauth_credentials_revoked: true }
    end

    # Google disables an account for a reason. Only a hijacked account needs
    # its tokens revoked.
    def handle_account_disabled(user)
      Rails.logger.info("RISC: account_disabled for user #{user.id}, reason: #{event_data[:reason]}")
      return { action: "account_disabled", reason: event_data[:reason] } unless event_data[:reason] == "hijacking"

      revoke_all_oauth_credentials(user)
      { action: "account_disabled_hijacking", oauth_credentials_revoked: true }
    end

    def handle_verification_event
      Rails.logger.info("RISC: Verification event received, state: #{event_data[:state]}")
      @security_event.mark_processed!
      { action: "verification", state: event_data[:state] }
    end

    # Tries every credential, so one failure does not keep the others alive, then
    # raises if any failed.
    def revoke_all_oauth_credentials(user)
      failures = []

      user.oauth_credentials.google.each do |credential|
        credential.destroy!
        Rails.logger.info("Revoked OAuth credential #{credential.id} for user #{user.id}")
      rescue => e
        Rails.error.report(e, handled: true, context: { oauth_credential_id: credential.id })
        failures << "credential #{credential.id}: #{e.class}: #{e.message}"
      end

      raise RevocationFailed, "Could not revoke #{failures.join('; ')}" if failures.any?
    end
  end
end
