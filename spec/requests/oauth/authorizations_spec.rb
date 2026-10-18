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
      scope:                 McpTools::Scopes::NAMES.join(" "),
      state:                 "abc",
      code_challenge:        "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
      code_challenge_method: "S256"
    }
  end

  before { sign_in user }

  # The checkbox of one scope on the consent page: "checked", "unchecked", or
  # nil when the page has no box for it.
  def box(scope)
    input = Nokogiri::HTML(response.body).at_css("input[name='scopes[]'][value='#{scope}']")
    return if input.nil?

    input["checked"] ? "checked" : "unchecked"
  end

  it "shows the client name, the redirect host, and a box for each scope" do
    get "/api/oauth/authorize", params: params

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Connect Claude?", "claude.ai", "busy times", user.email, "Your schedule")
    expect(box("schedule:read")).to eq("checked")
    expect(box("settings:write")).to eq("unchecked")
    expect(box("friends:requests")).to eq("unchecked")
    expect(box("catalog")).to be_nil
  end

  def granted_scopes
    location = URI(response.location)
    code     = Rack::Utils.parse_query(location.query).fetch("code")
    Doorkeeper::AccessGrant.by_token(code).scopes.to_a
  end

  it "grants the always-on scope and the boxes the student checked" do
    post "/api/oauth/authorize", params: params.merge(scopes: %w[schedule:read friends:read settings:write])

    expect(granted_scopes).to eq(%w[catalog schedule:read friends:read settings:write])
  end

  it "grants only the always-on scope when no box is checked" do
    post "/api/oauth/authorize", params: params

    expect(granted_scopes).to eq([ "catalog" ])
  end

  it "shows the read boxes for a client that still asks for the legacy read scope" do
    get "/api/oauth/authorize", params: params.merge(scope: "read")

    expect(response).to have_http_status(:ok)
    expect(box("friends:read")).to eq("checked")
    expect(response.body).not_to include("It can change")

    post "/api/oauth/authorize", params: params.merge(scope: "read", scopes: %w[schedule:read])
    expect(granted_scopes).to eq(%w[catalog schedule:read])
  end

  it "checks a change box the student gave this app before" do
    create(:oauth_access_token, resource_owner_id: user.id, application: application, scopes: "catalog settings:write")

    get "/api/oauth/authorize", params: params

    expect(box("settings:write")).to eq("checked")
    expect(box("notifications:write")).to eq("unchecked")
  end

  it "checks the boxes of a step-up request for fewer scopes" do
    get "/api/oauth/authorize", params: params.merge(scope: "catalog schedule:read notifications:write")

    expect(box("notifications:write")).to eq("checked")
    expect(box("friends:requests")).to be_nil
  end

  it "lets a client registered before the scopes were split ask for the new scopes" do
    application.update!(dynamic: true, scopes: "read")

    get "/api/oauth/authorize", params: params

    expect(response).to have_http_status(:ok)
    expect(application.reload.scopes.to_a).to eq(McpTools::Scopes::NAMES)
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
