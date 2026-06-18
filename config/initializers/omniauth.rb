# frozen_string_literal: true

Rails.application.config.middleware.use OmniAuth::Builder do
  redirect_uri = if Rails.env.production?
    host = ENV.fetch("APPLICATION_HOST", "calendar.witcc.dev")
    "https://#{host}/auth/google_oauth2/callback"
  end

  provider(
    :google_oauth2,
    Rails.application.credentials.dig(:google, :client_id),
    Rails.application.credentials.dig(:google, :client_secret),
    {
      scope: [
        "email",
        "profile",
        "https://www.googleapis.com/auth/calendar",
        "https://www.googleapis.com/auth/calendar.calendars",
        "https://www.googleapis.com/auth/calendar.app.created"
      ].join(" "),
      access_type: "offline",
      prompt: "consent",
      include_granted_scopes: true,
      redirect_uri: redirect_uri
    }.compact
  )
end

OmniAuth.config.logger = Rails.logger
OmniAuth.config.allowed_request_methods = %i[get post]
OmniAuth.config.silence_get_warning = true
