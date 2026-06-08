# frozen_string_literal: true

class RevokeOauthCredentialJob < ApplicationJob
  queue_as :default

  def perform(credential_id)
    credential = OauthCredential.find_by(id: credential_id)
    return unless credential

    revoke_token_with_google(credential.access_token)
    credential.destroy

    Rails.logger.info "Successfully revoked OAuth credential #{credential_id} for #{credential.email}"
  end

  private

  def revoke_token_with_google(access_token)
    require "net/http"
    require "uri"

    uri      = URI("https://oauth2.googleapis.com/revoke")
    response = Net::HTTP.post_form(uri, { "token" => access_token })

    case response.code
    when "200" then Rails.logger.info "OAuth token revoked with Google successfully"
    when "400" then Rails.logger.warn "OAuth token may already be revoked or invalid (HTTP 400)"
    else Rails.logger.warn "Google OAuth revocation returned: HTTP #{response.code}"
    end
  rescue => e
    Rails.logger.error "Error revoking OAuth token with Google: #{e.message}"
  end
end
