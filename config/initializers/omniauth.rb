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

  # Sign in with Microsoft (Entra ID v2). Off unless MicrosoftSignIn.enabled?:
  # the request_path lambda starts the sign-in only on a POST while the flag is
  # on and the client is configured, so any other request falls through to a
  # 404. The setup phase reads the client settings per request. Sign-in scopes
  # only: calendar access is the Microsoft Graph provider's job.
  #
  # The strings match MicrosoftSignIn::PROVIDER, SCOPE and CALLBACK_PATH. They
  # are literals because this block runs at boot, before app code may autoload.
  # The lambdas run per request, so they can call MicrosoftSignIn.
  provider(
    :entra_id,
    {
      name:          "microsoft",
      scope:         "openid email profile",
      pkce:          true,
      request_path:  ->(env) { MicrosoftSignIn.request_phase?(env) },
      callback_path: "/auth/microsoft/callback",
      setup:         ->(env) { MicrosoftSignIn.configure_strategy(env["omniauth.strategy"]) }
    }
  )
end

OmniAuth.config.logger = Rails.logger
OmniAuth.config.allowed_request_methods = %i[get post]
OmniAuth.config.silence_get_warning = true
