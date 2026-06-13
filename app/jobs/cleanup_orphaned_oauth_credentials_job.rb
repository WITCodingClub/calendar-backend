# frozen_string_literal: true

class CleanupOrphanedOauthCredentialsJob < ApplicationJob
  queue_as :low

  def perform
    Rails.logger.info "[CleanupOrphanedOauthCredentialsJob] Starting orphaned OAuth credential cleanup"

    deleted_count = 0
    error_count = 0

    orphaned_credentials = find_orphaned_credentials

    Rails.logger.info "[CleanupOrphanedOauthCredentialsJob] Found #{orphaned_credentials.size} orphaned credentials"

    orphaned_credentials.each do |credential|
      reason = determine_orphan_reason(credential)
      Rails.logger.info "[CleanupOrphanedOauthCredentialsJob] Deleting credential #{credential.id} " \
                        "(email: #{credential.email}) - Reason: #{reason}"

      revoke_token_with_google(credential.access_token)
      credential.destroy!
      deleted_count += 1
    rescue => e
      error_count += 1
      Rails.logger.error "[CleanupOrphanedOauthCredentialsJob] Failed to delete credential #{credential.id}: #{e.message}"
    end

    Rails.logger.info "[CleanupOrphanedOauthCredentialsJob] Completed: #{deleted_count} deleted, #{error_count} errors"

    { deleted: deleted_count, errors: error_count }
  end

  private

  def find_orphaned_credentials
    orphaned_ids = []

    # Find credentials whose user no longer exists
    orphaned_by_user_sql = <<~SQL.squish
      SELECT oauth_credentials.id
      FROM oauth_credentials
      LEFT OUTER JOIN users ON users.id = oauth_credentials.user_id
      WHERE users.id IS NULL
    SQL
    orphaned_by_user = ActiveRecord::Base.connection.execute(orphaned_by_user_sql).to_a.pluck("id")
    orphaned_ids.concat(orphaned_by_user)

    # Find credentials with expired tokens that cannot be refreshed
    orphaned_by_expired_token = OauthCredential.where(token_expires_at: ..Time.current)
                                               .where(refresh_token: nil)
                                               .pluck(:id)
    orphaned_ids.concat(orphaned_by_expired_token)

    OauthCredential.where(id: orphaned_ids.uniq).includes(:user, :google_calendar)
  end

  def determine_orphan_reason(credential)
    return "Missing user" if credential.user.blank?

    if credential.token_expires_at.present? &&
       credential.token_expires_at <= Time.current &&
       credential.refresh_token.blank?
      return "Expired token without refresh capability"
    end

    "Unknown reason"
  end

  def revoke_token_with_google(access_token)
    require "net/http"
    require "uri"

    uri = URI("https://oauth2.googleapis.com/revoke")
    response = Net::HTTP.post_form(uri, { "token" => access_token })

    case response.code
    when "200"
      Rails.logger.info "[CleanupOrphanedOauthCredentialsJob] Token revoked with Google successfully"
    when "400"
      Rails.logger.warn "[CleanupOrphanedOauthCredentialsJob] Token may already be revoked or invalid (HTTP 400)"
    else
      Rails.logger.warn "[CleanupOrphanedOauthCredentialsJob] Google OAuth revocation returned: HTTP #{response.code}"
    end
  rescue => e
    Rails.logger.error "[CleanupOrphanedOauthCredentialsJob] Error revoking token: #{e.message}"
  end
end
