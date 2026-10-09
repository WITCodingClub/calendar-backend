# frozen_string_literal: true

require "net/http"
require "uri"

module GoogleSignIn
  # Ends a Google grant. OauthCredential enqueues it after a credential is
  # destroyed, so a disconnect answers without waiting for Google.
  class RevokeTokenJob < ApplicationJob
    queue_as :default

    REVOKE_URL = "https://oauth2.googleapis.com/revoke"

    class RevocationFailed < StandardError; end

    # The argument is a live token. Keep it out of the job logs.
    self.log_arguments = false

    retry_on RevocationFailed, Net::OpenTimeout, Net::ReadTimeout, SocketError,
             Errno::ECONNREFUSED, Errno::ECONNRESET,
             wait: :polynomially_longer, attempts: 5

    # Solid Queue stores job arguments in solid_queue_jobs, and keeps the row
    # after the job finishes. So the caller passes the token encrypted with
    # the Active Record encryption key, not in plain text.
    def self.seal(token)
      ActiveRecord::Encryption.encryptor.encrypt(token) if token.present?
    end

    def perform(sealed_token)
      token = unseal(sealed_token)
      return if token.blank?

      response = Net::HTTP.post_form(URI(REVOKE_URL), { "token" => token })

      case response.code
      when "200" then Rails.logger.info "[GoogleSignIn::RevokeTokenJob] Google revoked the grant"
      # Google answers 400 for a token that is already revoked or expired.
      when "400" then Rails.logger.warn "[GoogleSignIn::RevokeTokenJob] Token already revoked or invalid (HTTP 400)"
      else
        raise RevocationFailed, "Google did not revoke the token (HTTP #{response.code})"
      end
    end

    private

    # A job enqueued before the deploy that added seal holds the plain token.
    def unseal(value)
      return value if value.blank?

      encryptor = ActiveRecord::Encryption.encryptor
      encryptor.encrypted?(value) ? encryptor.decrypt(value) : value
    end
  end
end
