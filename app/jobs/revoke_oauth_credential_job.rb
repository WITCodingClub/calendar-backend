# frozen_string_literal: true

class RevokeOauthCredentialJob < ApplicationJob
  queue_as :default

  # Revoke an OAuth credential with Google and delete it from the database
  # @param credential_id [Integer] The ID of the OauthCredential to revoke
  def perform(credential_id)
    credential = OauthCredential.find_by(id: credential_id)

    # If credential was already deleted, just return
    return unless credential

    # Revoke token with Google
    revoke_token_with_google(credential.access_token)

    # Delete from database (will also destroy associated google_calendar due to dependent: :destroy)
    credential.destroy

    Rails.logger.info "Successfully revoked OAuth credential #{credential_id} for #{credential.email}"
  end

  private

  def revoke_token_with_google(access_token)
    require "net/http"
    require "uri"

    uri = URI("https://oauth2.googleapis.com/revoke")
    response = Net::HTTP.post_form(uri, { "token" => access_token })

    case response.code
    when "200"
      Rails.logger.info "OAuth token revoked with Google successfully"
    when "400"
      Rails.logger.warn "OAuth token may already be revoked or invalid (HTTP 400)"
    else
      Rails.logger.warn "Google OAuth revocation returned: HTTP #{response.code}"
    end
  rescue => e
    Rails.logger.error "Error revoking OAuth token with Google: #{e.message}"
    # Continue with database deletion even if Google revocation fails
  end

end
