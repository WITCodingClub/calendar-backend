# frozen_string_literal: true

module Cleanup
  # Deletes the OAuth clients that MCP clients registered themselves (at
  # /api/oauth/register, or with a client ID metadata document) and that hold
  # no token. claude.ai registers a new client for each connection, so most
  # clients never get a token. A day is enough time to finish a sign-in. A
  # metadata document client comes back on its next sign-in. Deleting an
  # application also deletes its grants and tokens.
  class UnusedOauthClientsJob < ApplicationJob
    queue_as :low

    UNUSED_AFTER = 1.day

    def perform
      tokens = Doorkeeper::AccessToken.where(revoked_at: nil).select(:application_id)

      deleted = Doorkeeper::Application
                .where(dynamic: true, created_at: ...UNUSED_AFTER.ago)
                .where.not(id: tokens)
                .destroy_all
                .size

      Rails.logger.info "[Cleanup::UnusedOauthClientsJob] Deleted #{deleted} unused OAuth clients"
    end
  end
end
