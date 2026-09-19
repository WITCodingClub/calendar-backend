# frozen_string_literal: true

class RefreshOauthTokensJob < ApplicationJob
  queue_as :low

  REFRESH_THRESHOLD = 7.days

  def perform
    credentials_to_refresh = OauthCredential.where(provider: refreshable_providers)
                                            .where(updated_at: ...REFRESH_THRESHOLD.ago)
                                            .where.not(refresh_token: nil)

    total         = credentials_to_refresh.count
    success_count = 0
    failure_count = 0
    revoked_count = 0

    Rails.logger.info "[RefreshOauthTokensJob] Starting refresh of #{total} OAuth credentials"

    credentials_to_refresh.find_each do |credential|
      case refresh_credential(credential)
      when :success  then success_count += 1
      when :revoked  then revoked_count += 1
      when :failure  then failure_count += 1
      end
    end

    Rails.logger.info "[RefreshOauthTokensJob] Completed: #{success_count} refreshed, #{failure_count} failed, #{revoked_count} revoked"

    return unless failure_count > 5 || revoked_count > 5

    Rails.logger.warn "[RefreshOauthTokensJob] High failure rate detected - #{failure_count} failures, #{revoked_count} revoked"
  end

  private

  # Microsoft credentials refresh only while the app has an Entra client.
  def refreshable_providers
    MicrosoftGraph.configured? ? %w[google microsoft] : %w[google]
  end

  def refresh_credential(credential)
    return refresh_microsoft_credential(credential) if credential.provider == "microsoft"

    google_credentials = Google::Auth::UserRefreshCredentials.new(
      client_id:     Rails.application.credentials.dig(:google, :client_id),
      client_secret: Rails.application.credentials.dig(:google, :client_secret),
      refresh_token: credential.refresh_token,
      scope:         [ "https://www.googleapis.com/auth/calendar" ]
    )

    google_credentials.refresh!

    credential.update!(
      access_token:      google_credentials.access_token,
      token_expires_at:  Time.current + google_credentials.expires_in.seconds
    )

    Rails.logger.info "[RefreshOauthTokensJob] Refreshed token for credential #{credential.id} (#{credential.email})"
    :success
  rescue Signet::AuthorizationError => e
    Rails.logger.warn "[RefreshOauthTokensJob] Token revoked for credential #{credential.id} (#{credential.email}): #{e.message}"
    credential.update!(
      metadata: (credential.metadata || {}).merge(
        "token_revoked"     => true,
        "token_revoked_at"  => Time.current.iso8601,
        "revocation_reason" => e.message
      )
    )
    :revoked
  rescue => e
    Rails.logger.error "[RefreshOauthTokensJob] Failed to refresh credential #{credential.id} (#{credential.email}): #{e.message}"
    :failure
  end

  # Microsoft refresh tokens expire after 90 days without use, so a weekly
  # refresh keeps an idle connection alive. TokenClient marks the credential
  # revoked when Microsoft answers invalid_grant.
  def refresh_microsoft_credential(credential)
    MicrosoftGraph::TokenClient.new.refresh!(credential)

    Rails.logger.info "[RefreshOauthTokensJob] Refreshed Microsoft token for credential #{credential.id}"
    :success
  rescue MicrosoftGraph::AuthError => e
    if credential.token_revoked?
      Rails.logger.warn "[RefreshOauthTokensJob] Microsoft token revoked for credential #{credential.id}"
      :revoked
    else
      Rails.logger.error "[RefreshOauthTokensJob] Failed to refresh Microsoft credential #{credential.id}: #{e.message}"
      :failure
    end
  rescue => e
    Rails.logger.error "[RefreshOauthTokensJob] Failed to refresh Microsoft credential #{credential.id}: #{e.message}"
    :failure
  end
end
