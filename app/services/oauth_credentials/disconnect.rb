# frozen_string_literal: true

module OauthCredentials
  # Removes one connected account, for the API and the dashboard. The model's
  # destroy callbacks revoke the grant and stop the calendar sharing.
  module Disconnect
    # Returns false, and keeps the account, when it is the last Google account:
    # that account signs the person in (OauthCredential#removable?).
    def self.call(credential)
      return false unless credential.removable?

      credential.destroy!
      true
    end
  end
end
