# frozen_string_literal: true

# OAuth 2.1 authorization server for MCP clients. docs/mcp.md has the flow.
#
# MCP clients are public clients: they register through POST /api/oauth/register,
# have no secret, and must use PKCE with S256. Tokens from this server give
# access to the MCP endpoint only. The extension API keeps its own JWTs.
Doorkeeper.configure do
  orm :active_record

  # A signed-out user goes to the sign-in page and comes back to the consent
  # page. ApplicationController#after_sign_in_path_for reads the stored path.
  resource_owner_authenticator do
    current_user || begin
      store_location_for(:user, request.fullpath)
      redirect_to new_user_session_path
      nil
    end
  end

  grant_flows %w[authorization_code]

  force_pkce
  pkce_code_challenge_methods %w[S256]

  authorization_code_expires_in 5.minutes
  access_token_expires_in 1.hour

  # Each refresh gives a new refresh token. The old one stops working after the
  # client uses the new access token (the previous_refresh_token column).
  use_refresh_token

  hash_token_secrets
  hash_application_secrets

  default_scopes :read
  enforce_configured_scopes

  access_token_methods :from_bearer_authorization

  # Claude Code and other local clients use a loopback redirect URI.
  force_ssl_in_redirect_uri { |uri| !Oauth::RedirectUris.loopback?(uri) }

  # Every client is a stranger that named itself, so the user always sees the
  # consent page.
  skip_authorization { false }

  handle_auth_errors :render

  # No resource server needs to look tokens up: Api::McpController reads the
  # database itself.
  allow_token_introspection false
end
