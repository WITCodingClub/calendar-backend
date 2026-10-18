# frozen_string_literal: true

module Oauth
  # Serves the OAuth discovery documents for MCP clients. See Oauth::Metadata.
  # No session and no token: a client reads these before it has either.
  class MetadataController < ActionController::API
    CACHE_AGE = 1.hour

    before_action { expires_in CACHE_AGE, public: true }

    def authorization_server
      render json: metadata.authorization_server
    end

    # Clients ask for /.well-known/oauth-protected-resource and for the same
    # path with the MCP path after it (RFC 9728 section 3.1). Both get the
    # one document.
    def protected_resource
      render json: metadata.protected_resource
    end

    private

    def metadata
      Oauth::Metadata.new(host: request.host, port: request.port, protocol: request.protocol)
    end
  end
end
