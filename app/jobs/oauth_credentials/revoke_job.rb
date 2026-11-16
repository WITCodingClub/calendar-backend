# frozen_string_literal: true

module OauthCredentials
  class RevokeJob < ApplicationJob
    queue_as :default

    def perform(credential_id)
      credential = OauthCredential.find_by(id: credential_id)
      return unless credential

      # The destroy callbacks remove the course calendar while the token still
      # works. After the commit, the provider ends the grant (revoke_later).
      credential.destroy!

      Rails.logger.info "Revoked OAuth credential #{credential_id} for #{credential.email}"
    end
  end
end
