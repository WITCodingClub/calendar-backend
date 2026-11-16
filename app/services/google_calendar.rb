# frozen_string_literal: true

# Settings of the Google OAuth clients, for the calendar provider and for
# "Sign in with Google". One web client serves both, the same way one Entra
# registration serves MicrosoftGraph and MicrosoftSignIn.
module GoogleCalendar
  AUTHORIZE_URL = "https://accounts.google.com/o/oauth2/auth"
  TOKEN_URL     = "https://oauth2.googleapis.com/token"

  CALENDAR_SCOPE = "https://www.googleapis.com/auth/calendar"

  # What the web client asks for at sign-in and at a calendar connection.
  # calendar.calendars and calendar.app.created let the app make and manage
  # the course calendar.
  SCOPES = [
    "email",
    "profile",
    CALENDAR_SCOPE,
    "https://www.googleapis.com/auth/calendar.calendars",
    "https://www.googleapis.com/auth/calendar.app.created"
  ].freeze

  module_function

  def config
    credentials = Rails.application.credentials

    {
      client_id:               credentials.dig(:google, :client_id).presence,
      client_secret:           credentials.dig(:google, :client_secret).presence,
      extension_client_id:     ENV["GOOGLE_EXTENSION_CLIENT_ID"].presence || credentials.dig(:google, :extension_client_id).presence,
      extension_client_secret: ENV["GOOGLE_EXTENSION_CLIENT_SECRET"].presence || credentials.dig(:google, :extension_client_secret).presence
    }
  end

  # The client ids that a Google token may be issued to: the web client and
  # each id in GOOGLE_OAUTH_CLIENT_IDS (comma separated), such as the
  # extension's own client. A token from any other client is refused, so a
  # token that another app got cannot be replayed here.
  def client_ids
    ids = ENV["GOOGLE_OAUTH_CLIENT_IDS"].to_s.split(",").map(&:strip)
    (ids << config[:client_id]).compact_blank.uniq
  end

  # The OmniAuth setup phase. Reads the settings per request, so the
  # initializer needs no app code at boot.
  def configure_strategy(strategy)
    settings = config

    strategy.options.client_id     = settings[:client_id]
    strategy.options.client_secret = settings[:client_secret]
    strategy.options.scope         = SCOPES.join(" ")
  end
end
