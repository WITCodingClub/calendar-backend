# frozen_string_literal: true

# This job proactively refreshes OAuth tokens to prevent them from expiring.
#
# Google refresh tokens can expire if:
# - Not used for 6 months (for apps in "testing" mode)
# - User revokes access
# - User changes password
# - Too many refresh tokens issued (Google limits to 50 per user per client)
#
# By running this job weekly, we ensure all tokens stay active and don't expire
# due to inactivity.
class RefreshOauthTokensJob < ApplicationJob
  queue_as :low

  # Refresh tokens that haven't been refreshed in the last 7 days
  REFRESH_THRESHOLD = 7.days

  def perform
    credentials_to_refresh = OauthCredential.google
                                            .where("updated_at < ?", REFRESH_THRESHOLD.ago)
                                            .where.not(refresh_token: nil)

    total = credentials_to_refresh.count
    success_count = 0
    failure_count = 0
    revoked_count = 0

    Rails.logger.info "[RefreshOauthTokensJob] Starting refresh of #{total} OAuth credentials"

    credentials_to_refresh.find_each do |credential|
      result = refresh_credential(credential)

      case result
      when :success
        success_count += 1
      when :revoked
        revoked_count += 1
      when :failure
        failure_count += 1
      end
    end

    Rails.logger.info "[RefreshOauthTokensJob] Completed: #{success_count} refreshed, #{failure_count} failed, #{revoked_count} revoked"

    # Send alert if there are many failures
    if failure_count > 5 || revoked_count > 5
      Rails.logger.warn "[RefreshOauthTokensJob] High failure rate detected - #{failure_count} failures, #{revoked_count} revoked"
      # Could add email notification here in the future
    end
  end

  private

  def refresh_credential(credential)
    google_credentials = Google::Auth::UserRefreshCredentials.new(
      client_id: Rails.application.credentials.dig(:google, :client_id),
      client_secret: Rails.application.credentials.dig(:google, :client_secret),
      refresh_token: credential.refresh_token,
      scope: ["https://www.googleapis.com/auth/calendar"]
    )

    google_credentials.refresh!

    credential.update!(
      access_token: google_credentials.access_token,
      token_expires_at: Time.current + google_credentials.expires_in.seconds
    )

    Rails.logger.info "[RefreshOauthTokensJob] Refreshed token for credential #{credential.id} (#{credential.email})"
    :success
  rescue Signet::AuthorizationError => e
    # Token was revoked by user or Google
    Rails.logger.warn "[RefreshOauthTokensJob] Token revoked for credential #{credential.id} (#{credential.email}): #{e.message}"

    # Mark the credential as needing re-authentication
    credential.update!(
      metadata: (credential.metadata || {}).merge(
        "token_revoked" => true,
        "token_revoked_at" => Time.current.iso8601,
        "revocation_reason" => e.message
      )
    )

    :revoked
  rescue => e
    Rails.logger.error "[RefreshOauthTokensJob] Failed to refresh credential #{credential.id} (#{credential.email}): #{e.message}"
    :failure
  end
end
