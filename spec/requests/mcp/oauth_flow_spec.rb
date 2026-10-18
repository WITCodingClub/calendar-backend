# frozen_string_literal: true

require "rails_helper"

# The whole path an MCP client takes (docs/mcp.md): the 401 challenge,
# discovery, registration, sign-in and consent, the code exchange with PKCE,
# a tool call, a refresh, and a disconnect from Settings.
RSpec.describe "MCP OAuth flow", type: :request do
  let(:redirect_uri)  { "https://claude.ai/api/mcp/auth_callback" }
  let(:code_verifier) { SecureRandom.urlsafe_base64(48) }
  let(:code_challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false) }
  let(:resource) { "http://www.example.com/api/mcp" }
  let(:mcp_headers) { { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream" } }

  before do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider:    "google_oauth2",
      uid:         "google-uid-mcp",
      info:        { email: "mcp.student@wit.edu", first_name: "Mcp", last_name: "Student" },
      credentials: { token: "synthetic-access-token", expires_at: 1.hour.from_now.to_i },
      extra:       { raw_info: { granted_scopes: "email profile" } }
    )
  end

  after do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  def mcp_call(token, method, params = {})
    post "/api/mcp",
         params:  { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json,
         headers: mcp_headers.merge("Authorization" => "Bearer #{token}")
  end

  def authorize_params(client_id)
    {
      client_id:             client_id,
      redirect_uri:          redirect_uri,
      response_type:         "code",
      scope:                 McpTools::Scopes::NAMES.join(" "),
      state:                 "client-state",
      code_challenge:        code_challenge,
      code_challenge_method: "S256",
      resource:              resource
    }
  end

  it "signs in a client from the first 401 to a revoked token" do
    # 1. No token: the challenge points to the protected resource metadata.
    post "/api/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json, headers: mcp_headers
    expect(response).to have_http_status(:unauthorized)
    challenge = response.headers["WWW-Authenticate"]
    metadata_url = challenge[/resource_metadata="([^"]+)"/, 1]
    expect(metadata_url).to eq("http://www.example.com/.well-known/oauth-protected-resource")
    expect(challenge[/scope="([^"]+)"/, 1]).to eq(McpTools::Scopes::NAMES.join(" "))

    # 2. Discovery.
    get URI(metadata_url).path
    resource_metadata = response.parsed_body
    expect(resource_metadata["resource"]).to eq(resource)

    get "/.well-known/oauth-authorization-server"
    server_metadata = response.parsed_body
    expect(server_metadata["issuer"]).to eq(resource_metadata["authorization_servers"].first)
    expect(server_metadata["code_challenge_methods_supported"]).to eq([ "S256" ])

    # 3. Registration.
    post URI(server_metadata["registration_endpoint"]).path,
         params:  { client_name: "Claude", redirect_uris: [ redirect_uri ], token_endpoint_auth_method: "none" }.to_json,
         headers: { "Content-Type" => "application/json" }
    expect(response).to have_http_status(:created)
    client_id = response.parsed_body["client_id"]

    # 4. Signed out: the consent page sends the student to sign in and back.
    get "/api/oauth/authorize", params: authorize_params(client_id)
    expect(response).to redirect_to(new_user_session_path)
    get "/auth/google_oauth2/callback"
    back = URI(response.location)
    expect(back.path).to eq("/api/oauth/authorize")
    expect(Rack::Utils.parse_query(back.query)).to eq(authorize_params(client_id).transform_keys(&:to_s))

    get back.request_uri
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Connect Claude?", "claude.ai", "It can read", "It can change, if you allow it")

    # 5. Allow, with the schedule box and one change box checked: the browser
    # goes back to the client with a code.
    post "/api/oauth/authorize", params: authorize_params(client_id).merge(scopes: %w[schedule:read settings:write])
    callback = URI(response.location)
    expect("#{callback.scheme}://#{callback.host}#{callback.path}").to eq(redirect_uri)
    callback_params = Rack::Utils.parse_query(callback.query)
    expect(callback_params["state"]).to eq("client-state")

    # 6. Code exchange with the PKCE verifier.
    post "/api/oauth/token", params: {
      grant_type:    "authorization_code",
      code:          callback_params["code"],
      redirect_uri:  redirect_uri,
      client_id:     client_id,
      code_verifier: code_verifier,
      resource:      resource
    }
    expect(response).to have_http_status(:ok)
    tokens = response.parsed_body
    expect(tokens).to include("token_type" => "Bearer", "expires_in" => 3600, "scope" => "catalog schedule:read settings:write")

    # 7. The MCP server answers with the tools. A tool whose box was not
    # checked answers a tool error.
    mcp_call(tokens["access_token"], "tools/list")
    expect(response).to have_http_status(:ok)
    tool_names = response.parsed_body.dig("result", "tools").pluck("name")
    expect(tool_names).to match_array(McpTools.names)

    mcp_call(tokens["access_token"], "tools/call", { name: "list_friends", arguments: {} })
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("result", "isError")).to be(true)
    expect(response.parsed_body.dig("result", "content", 0, "text")).to include('"Your friends" permission')

    # 7b. The student has the app's permissions on the Settings page.
    get dashboard_settings_path
    expect(response.body).to include("Reads: Course catalog, Your schedule", "Changes: Change calendar settings")

    # 8. A refresh gives a new refresh token.
    post "/api/oauth/token", params: { grant_type: "refresh_token", refresh_token: tokens["refresh_token"], client_id: client_id }
    expect(response).to have_http_status(:ok)
    refreshed = response.parsed_body
    expect(refreshed["refresh_token"]).not_to eq(tokens["refresh_token"])

    mcp_call(refreshed["access_token"], "tools/list")
    expect(response).to have_http_status(:ok)

    # 9. The old refresh token stops working once the new token is used.
    post "/api/oauth/token", params: { grant_type: "refresh_token", refresh_token: tokens["refresh_token"], client_id: client_id }
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body["error"]).to eq("invalid_grant")

    # 10. The student disconnects the app in Settings.
    application = Doorkeeper::Application.find_by(uid: client_id)
    get dashboard_settings_path
    expect(response.body).to include("Connected apps", "Claude")

    delete dashboard_connected_app_path(application)
    expect(response).to redirect_to(dashboard_settings_path)

    mcp_call(refreshed["access_token"], "tools/list")
    expect(response).to have_http_status(:unauthorized)
    expect(response.headers["WWW-Authenticate"]).to include('error="invalid_token"')
  end

  it "refuses a code exchange without the PKCE verifier" do
    application = create(:oauth_application, redirect_uri: redirect_uri)
    sign_in create(:user)

    post "/api/oauth/authorize", params: authorize_params(application.uid)
    code = Rack::Utils.parse_query(URI(response.location).query)["code"]

    post "/api/oauth/token", params: {
      grant_type: "authorization_code", code: code, redirect_uri: redirect_uri, client_id: application.uid
    }

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body["error"]).to eq("invalid_request")
  end

  it "refuses the plain PKCE method" do
    application = create(:oauth_application, redirect_uri: redirect_uri)
    sign_in create(:user)

    get "/api/oauth/authorize", params: authorize_params(application.uid).merge(code_challenge_method: "plain")

    expect(response).to have_http_status(:bad_request)
    expect(response.body).to include("Cannot connect this app")
  end

  it "signs in a client that uses a client ID metadata document" do
    client_id = "https://claude.example/oauth/client-metadata.json"
    allow(Resolv).to receive(:getaddresses).with("claude.example").and_return([ "93.184.215.14" ])
    stub_request(:get, client_id).to_return(
      status: 200,
      body:   { client_id: client_id, client_name: "Claude", redirect_uris: [ redirect_uri ], token_endpoint_auth_method: "none" }.to_json
    )
    sign_in create(:user)

    post "/api/oauth/authorize", params: authorize_params(client_id)
    code = Rack::Utils.parse_query(URI(response.location).query)["code"]

    post "/api/oauth/token", params: {
      grant_type: "authorization_code", code: code, redirect_uri: redirect_uri,
      client_id: client_id, code_verifier: code_verifier
    }

    expect(response).to have_http_status(:ok)
    mcp_call(response.parsed_body["access_token"], "tools/list")
    expect(response).to have_http_status(:ok)
  end
end
