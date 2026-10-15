# frozen_string_literal: true

module Oauth
  # Client registration for MCP clients: dynamic client registration
  # (RFC 7591) and client ID metadata documents (Oauth::ClientMetadataDocument)
  # use the same rules.
  #
  # Every client registered here is public: it gets no secret and must use PKCE
  # (the Doorkeeper config forces S256). The client name is the client's own
  # claim, so the consent page also shows the redirect host.
  class ClientRegistration
    NAME_MAX_LENGTH = 100
    DEFAULT_NAME    = "MCP client"

    attr_reader :metadata

    def initialize(metadata)
      @metadata = metadata.to_h.with_indifferent_access
    end

    def call
      Doorkeeper::Application.create!(attributes)
    end

    # The application attributes, after the checks. Raises
    # InvalidClientMetadataError for metadata this server does not accept.
    def attributes
      validate!

      {
        name:         client_name,
        redirect_uri: redirect_uris.join("\n"),
        scopes:       McpTools::Scopes::NAMES.join(" "),
        confidential: false,
        dynamic:      true
      }
    end

    private

    def validate!
      if (message = RedirectUris.error_for(metadata[:redirect_uris]))
        raise InvalidClientMetadataError.new("invalid_redirect_uri", message)
      end

      auth_method = metadata[:token_endpoint_auth_method]
      if auth_method.present? && auth_method != "none"
        raise InvalidClientMetadataError.new("invalid_client_metadata", "token_endpoint_auth_method must be none")
      end

      # A client may list grants and response types that this server does not
      # offer, such as the JWT bearer grant in claude.ai's metadata document.
      # The server only needs the ones it uses, and it never issues the others.
      grant_types = Array(metadata[:grant_types].presence || %w[authorization_code])
      unless grant_types.include?("authorization_code")
        raise InvalidClientMetadataError.new("invalid_client_metadata", "the client must use the authorization_code grant")
      end

      response_types = Array(metadata[:response_types].presence || %w[code])
      return if response_types.include?("code")

      raise InvalidClientMetadataError.new("invalid_client_metadata", "the client must use the code response type")
    end

    def redirect_uris
      metadata[:redirect_uris]
    end

    def client_name
      name = metadata[:client_name].is_a?(String) ? metadata[:client_name].squish : ""
      name.presence&.first(NAME_MAX_LENGTH) || DEFAULT_NAME
    end
  end
end
