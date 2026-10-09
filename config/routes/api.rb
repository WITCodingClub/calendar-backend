# frozen_string_literal: true

# The JSON API: the public catalog API and the JWT API for the extension.
# Each api_*.rb file is drawn inside namespace :api, so its paths and
# controllers start with api/. Api::BaseController requires no token; a
# controller that needs a user calls authenticate_with_token.

namespace :api do
  draw :api_catalog  # public, read-only course data and GraphQL
  draw :api_user     # /api/user: the signed-in account
  draw :api_friends  # /api/friends and /api/meeting_links
  draw :api_calendar # courses, preferences, and university calendar events

  # Anonymous usage counts from the extension, for Grafana. No token.
  post "extension_events", to: "extension_events#create"

  # Content Security Policy violation reports from browsers. No token.
  post "csp_reports", to: "csp_reports#create"

  # Old paths. Before the catch-all, so they still match.
  draw :api_legacy

  match "*path", to: "catch_all#not_found", via: :all
end
