# frozen_string_literal: true

require "rails_helper"
require "webauthn/fake_client"

RSpec.describe "The passkey page", type: :request do
  ORIGIN = "http://localhost:3000"
  EXT    = "https://aceelinogfcceklkpacakdeddnaakicj.chromiumapp.org/"

  let(:user) { create(:user) }
  let(:token) { api_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }
  let(:client) { WebAuthn::FakeClient.new(ORIGIN) }

  def json = JSON.parse(response.body)

  describe "GET /passkey" do
    it "runs the ceremony for a link from our extension" do
      get "/passkey", params: { mode: "authenticate", redirect_uri: EXT }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sign in with a passkey")
    end

    it "refuses to send a code anywhere but our extension" do
      get "/passkey", params: { mode: "authenticate", redirect_uri: "https://evil.example.com/" }

      expect(response).to have_http_status(:bad_request)
      expect(response.body).to include("did not come from the WIT Calendar extension")
    end

    it "refuses a link with no redirect at all" do
      get "/passkey", params: { mode: "authenticate" }

      expect(response).to have_http_status(:bad_request)
    end

    it "refuses to register without the handoff that names the account" do
      get "/passkey", params: { mode: "register", redirect_uri: EXT }

      expect(response).to have_http_status(:bad_request)
    end

    it "keeps the device name the extension chose" do
      get "/passkey", params: { mode: "register", redirect_uri: EXT, handoff: "a-code", nickname: "legion-laptop" }

      expect(response.body).to include("legion-laptop")
    end

    it "registers when the extension supplied a handoff" do
      get "/passkey", params: { mode: "register", redirect_uri: EXT, handoff: "a-code" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Add a passkey")
    end

    it "still understands the older spelling of the sign-in mode" do
      get "/passkey", params: { mode: "signin", redirect_uri: EXT }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sign in with a passkey")
    end

    it "treats an unknown mode as sign-in rather than failing" do
      get "/passkey", params: { mode: "wat", redirect_uri: EXT }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sign in with a passkey")
    end
  end

  # api/passkeys_spec.rb covers the rest of the handoff. This is the page's
  # own risk: a leaked handle with no handoff and no token.
  describe "the handoff round trip" do
    it "will not register onto an account the caller cannot prove they hold" do
      post "/api/user/passkeys/handoff", headers: headers
      code = json["code"]
      post "/api/user/passkeys/registration_options", params: { handoff: code }
      handle    = json["handle"]
      challenge = json.dig("options", "challenge")

      # The handle alone is not authority — this is the leaked-handle case.
      post "/api/user/passkeys",
           params: { handle: handle, credential: client.create(challenge: challenge) },
           as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(user.passkeys.count).to eq(0)
    end
  end
end
