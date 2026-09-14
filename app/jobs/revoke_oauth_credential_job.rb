# frozen_string_literal: true

class RevokeOauthCredentialJob < ApplicationJob
  queue_as :default

  # Google did not confirm the revocation. The credential is already deleted
  # at that point, so a retry has nothing left to revoke. The failed job is the
  # record that the grant can still be live.
  class RevocationFailed < StandardError; end

  def perform(credential_id)
    credential = OauthCredential.find_by(id: credential_id)
    return unless credential

    # The refresh token ends the whole grant. An access token lasts one hour,
    # and Google does not revoke an access token that has expired.
    token = credential.refresh_token.presence || credential.access_token

    # Destroy first. Its callbacks remove the course calendar from the
    # account's calendar list, and that request needs the token to still work.
    credential.destroy!
    revoke_token_with_google(credential_id, token)

    Rails.logger.info "Successfully revoked OAuth credential #{credential_id} for #{credential.email}"
  end

  private

  def revoke_token_with_google(credential_id, token)
    require "net/http"
    require "uri"

    uri      = URI("https://oauth2.googleapis.com/revoke")
    response = Net::HTTP.post_form(uri, { "token" => token })

    case response.code
    when "200" then Rails.logger.info "OAuth token revoked with Google successfully"
    when "400" then Rails.logger.warn "OAuth token already revoked or invalid (HTTP 400)"
    else
      raise RevocationFailed,
            "Google did not revoke the token for OAuth credential #{credential_id} (HTTP #{response.code})"
    end
  end
end
