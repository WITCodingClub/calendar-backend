# frozen_string_literal: true

# Sign-in, account linking, and the pages the extension opens after OAuth.

get "/session/status", to: "auth_status#show"

# Google OAuth2 callback (handles both admin login and calendar OAuth)
get "/auth/google_oauth2/callback", to: "auth#google"

# Microsoft Graph calendar connection. Off unless the Flipper flag is on.
get "/auth/microsoft_graph",          to: "microsoft_auth#start",    as: :microsoft_graph_auth
get "/auth/microsoft_graph/callback", to: "microsoft_auth#callback", as: :microsoft_graph_auth_callback

# OAuth result pages (opened by Chrome extension)
# The passkey ceremony runs on this site, not in the extension, so the origin
# the browser reports stays the same for every browser and build.
get "/passkey", to: "passkeys#show"

# Signing in to the dashboard with the same passkey, ending in a Devise
# session rather than a token.
post "/users/passkey/options",  to: "users/passkey_sessions#options",  as: :passkey_session_options
post "/users/passkey/callback", to: "users/passkey_sessions#create",   as: :passkey_session

# Signing in to the dashboard with a WIT Microsoft account. OmniAuth starts it
# on POST /auth/microsoft. Off unless MicrosoftSignIn.enabled?.
get "/auth/microsoft/callback", to: "users/microsoft_sessions#create", as: :microsoft_sign_in_callback
get "/auth/failure", to: "users/microsoft_sessions#failure",
                     constraints: ->(request) { request.params[:strategy] == MicrosoftSignIn::PROVIDER }

get "/oauth/success", to: "oauth#success"
get "/oauth/failure", to: "oauth#failure"

# A Google account linked from a browser with no session waits here for the
# person to confirm it.
get    "/oauth/confirm", to: "oauth#confirm", as: :oauth_confirm
post   "/oauth/confirm", to: "oauth#link"
delete "/oauth/confirm", to: "oauth#cancel"
