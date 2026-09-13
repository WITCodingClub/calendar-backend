# frozen_string_literal: true

require "rails_helper"
require "webauthn/fake_client"

RSpec.describe "The passkey page", type: :request do
  ORIGIN = "http://localhost:3000"
  EXT    = "https://aceelinogfcceklkpacakdeddnaakicj.chromiumapp.org/"

  let(:user) { User.create!(email: "page@wit.edu", password: "password123", confirmed_at: Time.current) }
  let(:token) { api_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }
  let(:client) { WebAuthn::FakeClient.new(ORIGIN) }

  before { Flipper.enable(FlipperFlags::V1) }

  after { Flipper.disable(FlipperFlags::V1) }

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

  describe "the handoff round trip" do
    it "lets the page register a passkey using a code the extension minted" do
      post "/api/user/passkeys/handoff", headers: headers
      code = json["code"]
      expect(code).to be_present

      # The page holds no JWT — only the handoff.
      post "/api/user/passkeys/registration_options", params: { handoff: code }
      expect(response).to have_http_status(:ok)
      handle    = json["handle"]
      challenge = json.dig("options", "challenge")

      post "/api/user/passkeys",
           params: { handle: handle, handoff: code, credential: client.create(challenge: challenge) },
           as:     :json

      expect(response).to have_http_status(:created)
      expect(user.passkeys.count).to eq(1)
    end

    it "keeps the registration handoff alive across both calls, then spends it" do
      post "/api/user/passkeys/handoff", headers: headers
      code = json["code"]

      # Registration is two calls, so the handoff has to survive the first.
      post "/api/user/passkeys/registration_options", params: { handoff: code }
      expect(response).to have_http_status(:ok)
      handle    = json["handle"]
      challenge = json.dig("options", "challenge")

      post "/api/user/passkeys",
           params: { handle: handle, handoff: code, credential: client.create(challenge: challenge) },
           as: :json
      expect(response).to have_http_status(:created)

      # Spent now, so the link cannot register a second authenticator.
      post "/api/user/passkeys/registration_options", params: { handoff: code }
      expect(response).to have_http_status(:unauthorized)
    end

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

    it "refuses a made-up handoff" do
      post "/api/user/passkeys/registration_options", params: { handoff: "not-a-real-code" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns a code rather than a token when the page asks, then trades it" do
      # Register first, so there is something to sign in with.
      post "/api/user/passkeys/handoff", headers: headers
      reg_code = json["code"]
      post "/api/user/passkeys/registration_options", params: { handoff: reg_code }
      handle    = json["handle"]
      challenge = json.dig("options", "challenge")
      post "/api/user/passkeys",
           params: { handle: handle, handoff: reg_code, credential: client.create(challenge: challenge) },
           as: :json

      post "/api/user/passkeys/authentication_options"
      handle    = json["handle"]
      challenge = json.dig("options", "challenge")

      post "/api/user/passkeys/authenticate",
           params: { handle: handle, handoff: true, credential: client.get(challenge: challenge) },
           as:     :json

      expect(response).to have_http_status(:ok)
      expect(json["code"]).to be_present
      expect(json).not_to have_key("jwt")

      post "/api/user/passkeys/exchange", params: { code: json["code"] }

      expect(response).to have_http_status(:ok)
      expect(JsonWebTokenService.decode(json["jwt"])[:user_id]).to eq(user.id)
    end

    it "spends the session handoff on first use" do
      post "/api/user/passkeys/handoff", headers: headers
      reg_code = json["code"]
      post "/api/user/passkeys/registration_options", params: { handoff: reg_code }
      handle    = json["handle"]
      challenge = json.dig("options", "challenge")
      post "/api/user/passkeys",
           params: { handle: handle, handoff: reg_code, credential: client.create(challenge: challenge) },
           as: :json

      post "/api/user/passkeys/authentication_options"
      handle    = json["handle"]
      challenge = json.dig("options", "challenge")
      post "/api/user/passkeys/authenticate",
           params: { handle: handle, handoff: true, credential: client.get(challenge: challenge) },
           as: :json
      code = json["code"]

      post "/api/user/passkeys/exchange", params: { code: code }
      expect(response).to have_http_status(:ok)

      post "/api/user/passkeys/exchange", params: { code: code }
      expect(response).to have_http_status(:unauthorized)
    end

    it "will not trade a registration handoff for a session" do
      post "/api/user/passkeys/handoff", headers: headers

      post "/api/user/passkeys/exchange", params: { code: json["code"] }

      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses to mint a handoff without a token" do
      post "/api/user/passkeys/handoff"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
