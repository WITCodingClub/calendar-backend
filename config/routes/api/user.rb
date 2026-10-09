# frozen_string_literal: true

# /api/user: the signed-in account, its linked calendars, and its settings.
#
# Drawn inside namespace :api in config/routes/api.rb.

get "user", to: "profiles#show"

scope "user", as: :user do
  post "onboard", to: "onboardings#create"

  # Linked calendars and the OAuth credentials behind them
  post   "google_calendar",                  to: "google_calendars#create"
  post   "google_calendar/emails",           to: "google_calendars#add_email"
  delete "google_calendar/emails",           to: "google_calendars#remove_email"
  post   "microsoft_calendar",               to: "microsoft_calendars#create"
  patch  "microsoft_calendar",               to: "microsoft_calendars#update"
  get    "oauth_credentials",                to: "oauth_credentials#index"
  delete "oauth_credentials/:credential_id", to: "oauth_credentials#destroy"
  get    "busy_blocks",                      to: "busy_blocks#show"

  # Passkeys: a quick second sign-in for an account Google already vouched
  # for. The two authentication routes are the only unauthenticated ones.
  get    "passkeys",                        to: "passkeys#index"
  post   "passkeys/registration_options",   to: "passkeys#registration_options"
  post   "passkeys",                        to: "passkeys#create"
  delete "passkeys/:passkey_id",            to: "passkeys#destroy"
  post   "passkeys/handoff",                to: "passkeys#handoff"
  post   "passkeys/authentication_options", to: "passkeys#authentication_options"
  post   "passkeys/authenticate",           to: "passkeys#authenticate"
  post   "passkeys/exchange",               to: "passkeys#exchange"

  # Sessions: see where the account is signed in, and end any of them.
  get    "sessions",             to: "sessions#index"
  delete "sessions/:session_id", to: "sessions#destroy"
  post   "sessions/revoke_all",  to: "sessions#revoke_all"

  # Calendar sync state
  get "processed_events",        to: "processed_events#index"
  get "processed_events/status", to: "processed_events#processing_status"

  # Settings
  get   "extension_config",    to: "extension_configs#show"
  put   "extension_config",    to: "extension_configs#update"
  get   "feature_flags",       to: "feature_flags#index"
  get   "notifications",       to: "notifications#show"
  patch "notifications",       to: "notifications#update"
  get   "preferences/version", to: "preference_versions#show"
end
