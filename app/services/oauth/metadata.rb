# frozen_string_literal: true

module Oauth
  # The two discovery documents that MCP clients read before they sign in:
  #
  # - RFC 8414 authorization server metadata, at
  #   /.well-known/oauth-authorization-server
  # - RFC 9728 protected resource metadata for the MCP endpoint, at
  #   /.well-known/oauth-protected-resource
  #
  # The URLs come from the routes and the request host, the same as the other
  # discovery files (DiscoveryController).
  class Metadata
    SCOPES = %w[read].freeze

    def initialize(url_options)
      @url_options = url_options
    end

    def issuer
      routes.root_url(**@url_options).chomp("/")
    end

    def resource
      routes.api_mcp_url(**@url_options)
    end

    def resource_metadata_url
      routes.oauth_protected_resource_metadata_url(**@url_options)
    end

    def authorization_server
      {
        issuer:                                     issuer,
        authorization_endpoint:                     routes.oauth_authorization_url(**@url_options),
        token_endpoint:                             routes.oauth_token_url(**@url_options),
        revocation_endpoint:                        routes.oauth_revoke_url(**@url_options),
        registration_endpoint:                      routes.oauth_registration_url(**@url_options),
        scopes_supported:                           SCOPES,
        response_types_supported:                   %w[code],
        response_modes_supported:                   %w[query],
        grant_types_supported:                      %w[authorization_code refresh_token],
        token_endpoint_auth_methods_supported:      %w[none],
        revocation_endpoint_auth_methods_supported: %w[none],
        code_challenge_methods_supported:           %w[S256],
        client_id_metadata_document_supported:      true,
        service_documentation:                      routes.mcp_docs_url(**@url_options)
      }
    end

    def protected_resource
      {
        resource:                 resource,
        resource_name:            "WIT Calendar",
        authorization_servers:    [ issuer ],
        scopes_supported:         SCOPES,
        bearer_methods_supported: %w[header],
        resource_documentation:   routes.mcp_docs_url(**@url_options)
      }
    end

    private

    def routes
      Rails.application.routes.url_helpers
    end
  end
end
