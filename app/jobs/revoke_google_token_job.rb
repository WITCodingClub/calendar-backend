# frozen_string_literal: true

require "net/http"
require "uri"

# Ends a Google grant. OauthCredential enqueues it after a credential is
# destroyed, so a disconnect answers without waiting for Google.
class RevokeGoogleTokenJob < ApplicationJob
  queue_as :default

  REVOKE_URL = "https://oauth2.googleapis.com/revoke"

  class RevocationFailed < StandardError; end

  # The argument is a live token. Keep it out of the job logs.
  self.log_arguments = false

  retry_on RevocationFailed, Net::OpenTimeout, Net::ReadTimeout, SocketError,
           Errno::ECONNREFUSED, Errno::ECONNRESET,
           wait: :polynomially_longer, attempts: 5

  def perform(token)
    return if token.blank?

    response = Net::HTTP.post_form(URI(REVOKE_URL), { "token" => token })

    case response.code
    when "200" then Rails.logger.info "[RevokeGoogleTokenJob] Google revoked the grant"
    # Google answers 400 for a token that is already revoked or expired.
    when "400" then Rails.logger.warn "[RevokeGoogleTokenJob] Token already revoked or invalid (HTTP 400)"
    else
      raise RevocationFailed, "Google did not revoke the token (HTTP #{response.code})"
    end
  end
end
