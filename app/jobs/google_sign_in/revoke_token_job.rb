# frozen_string_literal: true

require "net/http"
require "uri"

module GoogleSignIn
  # Ends a Google grant. OauthCredential enqueues it after a credential is
  # destroyed, so a disconnect answers without waiting for Google.
  class RevokeTokenJob < ApplicationJob
    queue_as :default

    REVOKE_URL = "https://oauth2.googleapis.com/revoke"
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    class RevocationFailed < StandardError; end

    # The argument is a live token. Keep it out of the job logs.
    self.log_arguments = false

    retry_on RevocationFailed, Net::OpenTimeout, Net::ReadTimeout, SocketError,
             Errno::ECONNREFUSED, Errno::ECONNRESET,
             wait: :polynomially_longer, attempts: 5

    def perform(token)
      return if token.blank?

      uri = URI(REVOKE_URL)
      request = Net::HTTP::Post.new(uri)
      request.set_form_data("token" => token)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                 open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.request(request)
      end

      case response.code
      when "200" then Rails.logger.info "[GoogleSignIn::RevokeTokenJob] Google revoked the grant"
      # Google answers 400 for a token that is already revoked or expired.
      when "400" then Rails.logger.warn "[GoogleSignIn::RevokeTokenJob] Token already revoked or invalid (HTTP 400)"
      else
        raise RevocationFailed, "Google did not revoke the token (HTTP #{response.code})"
      end
    end
  end
end
