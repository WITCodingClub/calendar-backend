# frozen_string_literal: true

module OauthCredentials
  # Refreshes each credential that has not changed for a week
  # (OauthCredential.needs_refresh), so an idle connection stays alive. The
  # provider marks a credential revoked when it refuses the grant.
  class RefreshTokensJob < ApplicationJob
    queue_as :low

    def perform
      credentials = OauthCredential.needs_refresh.where(provider: CourseCalendars::Providers.refreshable_names)
      counts      = Hash.new(0)

      credentials.find_each { |credential| counts[refresh(credential)] += 1 }

      Rails.logger.info "[OauthCredentials::RefreshTokensJob] Completed: #{counts[:success]} refreshed, " \
                        "#{counts[:failure]} failed, #{counts[:revoked]} revoked"
      return unless counts[:failure] > 5 || counts[:revoked] > 5

      Rails.logger.warn "[OauthCredentials::RefreshTokensJob] High failure rate detected - " \
                        "#{counts[:failure]} failures, #{counts[:revoked]} revoked"
    end

    private

    def refresh(credential)
      credential.refresh!
      :success
    rescue StandardError => e
      if OauthCredential.invalid_grant?(e)
        Rails.logger.warn "[OauthCredentials::RefreshTokensJob] Token revoked for credential #{credential.id}"
        return :revoked
      end

      Rails.error.report(e, handled: true, context: { oauth_credential_id: credential.id })
      :failure
    end
  end
end
