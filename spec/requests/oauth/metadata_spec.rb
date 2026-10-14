# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Oauth::Metadata", type: :request do
  describe "GET /.well-known/oauth-authorization-server" do
    it "describes the server for public clients with PKCE" do
      get "/.well-known/oauth-authorization-server"

      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to include("public")
      expect(response.parsed_body).to include(
        "issuer"                                => "http://www.example.com",
        "authorization_endpoint"                => "http://www.example.com/api/oauth/authorize",
        "token_endpoint"                        => "http://www.example.com/api/oauth/token",
        "registration_endpoint"                 => "http://www.example.com/api/oauth/register",
        "revocation_endpoint"                   => "http://www.example.com/api/oauth/revoke",
        "code_challenge_methods_supported"      => [ "S256" ],
        "client_id_metadata_document_supported" => true,
        "token_endpoint_auth_methods_supported" => [ "none" ],
        "scopes_supported"                      => [ "read" ],
        "service_documentation"                 => "http://www.example.com/docs/mcp"
      )
    end
  end

  describe "GET /.well-known/oauth-protected-resource" do
    it "names the MCP endpoint and this server" do
      get "/.well-known/oauth-protected-resource"

      expect(response.parsed_body).to include(
        "resource"              => "http://www.example.com/api/mcp",
        "authorization_servers" => [ "http://www.example.com" ],
        "scopes_supported"      => [ "read" ]
      )
    end

    it "answers the same document with the MCP path after it" do
      get "/.well-known/oauth-protected-resource"
      root_document = response.parsed_body

      get "/.well-known/oauth-protected-resource/api/mcp"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(root_document)
    end
  end
end
