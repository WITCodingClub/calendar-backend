# frozen_string_literal: true

# Marks credentials that can no longer reach Google, so the person is asked to
# sign in again.
#
# A credential with an expired access token and no refresh token cannot get a
# new token. This job used to destroy it. That also deleted the course
# calendar and ended the person's sessions, and it asked Google to revoke an
# expired token, which Google always refuses. Now the job only sets the flag
# that needs_reauth? and the dashboard ("Needs re-auth") read. The next token
# from sign-in clears the flag (OauthCredential#clear_revoked_flag).
#
# The job no longer looks for credentials without a user. The foreign key on
# oauth_credentials.user_id makes that row impossible, so nothing is destroyed.
class CleanupOrphanedOauthCredentialsJob < ApplicationJob
  queue_as :low

  REASON = "access token expired and no refresh token"

  def perform
    flagged = 0

    unusable_credentials.find_each do |credential|
      credential.update!(
        metadata: (credential.metadata || {}).merge(
          "token_revoked"     => true,
          "token_revoked_at"  => Time.current.iso8601,
          "revocation_reason" => REASON
        )
      )
      flagged += 1
    end

    Rails.logger.info "[CleanupOrphanedOauthCredentialsJob] Marked #{flagged} credentials as needing sign-in again"

    { flagged: flagged }
  end

  private

  def unusable_credentials
    OauthCredential.where(token_expires_at: ..Time.current, refresh_token: nil)
                   .where("metadata->>'token_revoked' IS DISTINCT FROM 'true'")
  end
end
