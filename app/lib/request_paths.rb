# frozen_string_literal: true

# The paths that middleware and initializers match by hand, outside the router:
# Rack::Attack, Rack::Cors, the Content Security Policy report URI, and the
# meeting link log filter. config/routes draws the same paths, and
# spec/lib/request_paths_spec.rb checks that each one still routes.
module RequestPaths
  MCP = "/api/mcp"
  OAUTH_CLIENT = %w[/api/oauth/token /api/oauth/revoke /api/oauth/register].freeze
  OAUTH_METADATA_PREFIX = "/.well-known/oauth-"

  PUBLIC_CATALOG_PREFIX = "/api/v1/catalog"
  # /api/graphql only redirects to /api/v1/graphql.
  GRAPHQL = %w[/api/v1/graphql /api/graphql].freeze

  EXTENSION_EVENTS = "/api/extension_events"
  CSP_REPORTS = "/api/csp_reports"

  CALENDAR_FEED_PREFIX = "/calendar/"
  MEETING_LINK_PREFIX = "/meet/"
end
