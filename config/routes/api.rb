# frozen_string_literal: true

# The JSON API: the public catalog API and the JWT API for the extension.
# Each file in config/routes/api/ is drawn inside namespace :api, so its paths
# and controllers start with api/. Api::BaseController requires no token; a
# controller that needs a user calls authenticate_with_token.

namespace :api do
  draw "api/catalog"  # public, read-only course data and GraphQL
  draw "api/user"     # /api/user: the signed-in account
  draw "api/friends"  # /api/friends and /api/meeting_links
  draw "api/calendar" # courses, preferences, and university calendar events

  # The MCP server (docs/mcp.md). Its bearer tokens come from the OAuth server
  # in config/routes/oauth.rb, not from the extension sign-in. The server is
  # stateless, so GET (an event stream) and DELETE (end a session) answer 405.
  post  "mcp", to: "mcp#create", as: :mcp
  match "mcp", to: "mcp#method_not_allowed", via: %i[get delete]

  # Anonymous usage counts from the extension, for Grafana. No token.
  post "extension_events", to: "extension_events#create"

  # Content Security Policy violation reports from browsers. No token.
  post "csp_reports", to: "csp_reports#create"

  # Old paths. Before the catch-all, so they still match.
  draw "api/legacy"

  match "*path", to: "catch_all#not_found", via: :all
end
