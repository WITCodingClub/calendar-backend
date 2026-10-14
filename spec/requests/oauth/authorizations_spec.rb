# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Oauth::Authorizations", type: :request do
  let(:user) { create(:user) }
  let(:application) { create(:oauth_application, name: "Claude", redirect_uri: "https://claude.ai/api/mcp/auth_callback") }
  let(:params) do
    {
      client_id:             application.uid,
      redirect_uri:          "https://claude.ai/api/mcp/auth_callback",
      response_type:         "code",
      scope:                 "read",
      state:                 "abc",
      code_challenge:        "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
      code_challenge_method: "S256"
    }
  end

  before { sign_in user }

  it "shows the client name, the redirect host, and what it can read" do
    get "/api/oauth/authorize", params: params

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Connect Claude?", "claude.ai", "busy times", user.email)
  end

  it "widens form-action so the browser can follow the redirect to the client" do
    get "/api/oauth/authorize", params: params

    policy = response.headers["Content-Security-Policy-Report-Only"] || response.headers["Content-Security-Policy"]
    expect(policy).to include("form-action 'self' https: http://localhost:* http://127.0.0.1:*")
  end

  it "shows the page every time, even after an earlier approval" do
    post "/api/oauth/authorize", params: params
    get "/api/oauth/authorize", params: params

    expect(response).to have_http_status(:ok)
  end

  it "sends the client an access_denied error when the user denies" do
    delete "/api/oauth/authorize", params: params

    location = URI(response.location)
    expect(Rack::Utils.parse_query(location.query)).to include("error" => "access_denied", "state" => "abc")
  end

  it "accepts the MCP endpoint as the resource" do
    get "/api/oauth/authorize", params: params.merge(resource: "http://www.example.com/api/mcp")

    expect(response).to have_http_status(:ok)
  end

  it "refuses another resource" do
    get "/api/oauth/authorize", params: params.merge(resource: "https://evil.example/api")

    expect(response).to have_http_status(:bad_request)
    expect(response.body).to include("cannot issue a token for https://evil.example/api")
  end

  it "shows an error page for an unknown client" do
    get "/api/oauth/authorize", params: params.merge(client_id: "unknown")

    expect(response.body).to include("Cannot connect this app")
  end

  describe "a client ID metadata document" do
    let(:client_id) { "https://client.example/oauth/metadata.json" }
    let(:document) do
      { client_id: client_id, client_name: "Example Client", redirect_uris: [ "https://client.example/cb" ] }
    end
    let(:cimd_params) { params.merge(client_id: client_id, redirect_uri: "https://client.example/cb") }

    before { allow(Resolv).to receive(:getaddresses).with("client.example").and_return([ "93.184.215.14" ]) }

    it "fetches the document and names the domain that published it" do
      stub_request(:get, client_id).to_return(status: 200, body: document.to_json)

      get "/api/oauth/authorize", params: cimd_params

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Connect Example Client?", "client.example publishes this app")
    end

    it "shows an error page, with no redirect, when the document is wrong" do
      stub_request(:get, client_id).to_return(status: 200, body: document.merge(client_id: "https://evil.example/m.json").to_json)

      get "/api/oauth/authorize", params: cimd_params

      expect(response).to have_http_status(:bad_request)
      expect(response.body).to include("could not be checked")
    end
  end
end
