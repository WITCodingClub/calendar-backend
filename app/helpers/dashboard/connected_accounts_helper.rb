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

    # The text and the button for where an Outlook connection puts the course
    # events. `switch_to` is the placement that the button asks for.
    def microsoft_calendar_placement(calendar)
      if calendar.primary_placement?
        {
          text:      "Classes are in your main calendar and show as busy.",
          button:    "Use a separate calendar",
          switch_to: "separate",
          confirm:   "Move your classes to a separate \"WIT Courses\" calendar? They no longer show as busy to other people. Changes you made to class events in Outlook are lost."
        }
      else
        {
          text:      "Classes are in a separate \"WIT Courses\" calendar. They do not show as busy to other people.",
          button:    "Show classes as busy",
          switch_to: "primary",
          confirm:   "Move your classes to your main calendar? People who can see your calendar see the class events. The \"WIT Courses\" calendar is removed, and changes you made to class events in Outlook are lost."
        }
      end
    end
  end
end
