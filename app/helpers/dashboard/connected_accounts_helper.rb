# frozen_string_literal: true

module Dashboard
  module ConnectedAccountsHelper
    # The status of an Outlook calendar connection, for the badge on the
    # connected accounts page. `reconnect` is true when only a new Microsoft
    # sign-in can fix the connection.
    #
    # Access revoked: Microsoft refused the refresh token (invalid_grant).
    # Sign-in expired: the app has no refresh token to renew the access token.
    def microsoft_calendar_status(credential)
      if credential.token_revoked?
        { label: "Access revoked", badge: "m3-badge-error", reconnect: true }
      elsif credential.needs_reauth?
        { label: "Sign-in expired", badge: "m3-badge-error", reconnect: true }
      elsif credential.course_calendar.blank?
        { label: "No calendar", badge: "m3-badge-primary", reconnect: true }
      else
        { label: "Syncing", badge: "m3-badge-secondary", reconnect: false }
      end
    end
  end
end
