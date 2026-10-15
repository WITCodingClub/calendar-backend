# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Oauth::Registrations", type: :request do
  def register(body)
    post "/api/oauth/register", params: body.to_json, headers: { "Content-Type" => "application/json" }
  end

  def registrations = Yabeda.calendar.oauth_clients_registered_total.get({}) || 0

  it "registers a public client" do
    expect { register(client_name: "Claude", redirect_uris: [ "https://claude.ai/api/mcp/auth_callback" ]) }
      .to change(Doorkeeper::Application, :count).by(1)
      .and change { registrations }.by(1)

    expect(response).to have_http_status(:created)
    application = Doorkeeper::Application.last
    expect(application).to have_attributes(name: "Claude", confidential: false, dynamic: true, scopes: Doorkeeper::OAuth::Scopes.from_array(McpTools::Scopes::NAMES))
    expect(response.parsed_body).to include(
      "client_id"                  => application.uid,
      "redirect_uris"              => [ "https://claude.ai/api/mcp/auth_callback" ],
      "token_endpoint_auth_method" => "none"
    )
    expect(response.parsed_body).not_to have_key("client_secret")
  end

  it "accepts a loopback redirect for a local client" do
    register(client_name: "Claude Code", redirect_uris: [ "http://localhost:33418/callback" ])

    expect(response).to have_http_status(:created)
  end

  it "names a client with no name" do
    register(redirect_uris: [ "https://example.com/callback" ])

    expect(response.parsed_body["client_name"]).to eq(Oauth::ClientRegistration::DEFAULT_NAME)
  end

  it "refuses a plain HTTP redirect to another host" do
    register(redirect_uris: [ "http://example.com/callback" ])

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body["error"]).to eq("invalid_redirect_uri")
  end

  it "refuses a request with no redirect URIs" do
    register(client_name: "No redirect")

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body["error"]).to eq("invalid_redirect_uri")
  end

  it "refuses a confidential client" do
    register(redirect_uris: [ "https://example.com/callback" ], token_endpoint_auth_method: "client_secret_basic")

    expect(response.parsed_body["error"]).to eq("invalid_client_metadata")
  end

  it "refuses a client without the authorization_code grant" do
    register(redirect_uris: [ "https://example.com/callback" ], grant_types: [ "client_credentials" ])

    expect(response.parsed_body["error"]).to eq("invalid_client_metadata")
  end

  it "accepts extra grant types and returns only the ones it offers" do
    register(redirect_uris: [ "https://example.com/callback" ],
             grant_types: [ "authorization_code", "refresh_token", "urn:ietf:params:oauth:grant-type:jwt-bearer" ])

    expect(response).to have_http_status(:created)
    expect(response.parsed_body["grant_types"]).to eq(%w[authorization_code refresh_token])
  end

  it "refuses a client without the code response type" do
    register(redirect_uris: [ "https://example.com/callback" ], response_types: [ "token" ])

    expect(response.parsed_body["error"]).to eq("invalid_client_metadata")
  end

  it "refuses a body that is not a JSON object" do
    post "/api/oauth/register", params: "[1]", headers: { "Content-Type" => "application/json" }

    expect(response).to have_http_status(:bad_request)
  end
end
