# frozen_string_literal: true

# The OAuth 2.1 authorization server for MCP clients (docs/mcp.md).
# The extension does not use it: it keeps its own JWTs.
#
# The endpoints sit under /api, because the rproxy Worker sends /api straight
# to Rails. Other paths go to calendar-website first and reach Rails only on
# a 404, which is not a safe path for a POST.

# /api/oauth/authorize, /api/oauth/token, /api/oauth/revoke. The other
# Doorkeeper pages (the application admin, the token info endpoint) are not used.
use_doorkeeper scope: "api/oauth" do
  controllers authorizations: "oauth/authorizations"
  skip_controllers :applications, :authorized_applications, :token_info
end

# RFC 7591 dynamic client registration.
post "/api/oauth/register", to: "oauth/registrations#create", as: :oauth_registration

# RFC 8414 and RFC 9728 discovery. A client may add the MCP path after the
# protected resource path, so the suffix is optional. GET requests to
# /.well-known/ reach Rails (the website answers 404 for them).
get "/.well-known/oauth-authorization-server", to: "oauth/metadata#authorization_server",
                                               as: :oauth_authorization_server_metadata, format: false
get "/.well-known/oauth-protected-resource(/*resource_path)", to: "oauth/metadata#protected_resource",
                                                              as: :oauth_protected_resource_metadata, format: false
