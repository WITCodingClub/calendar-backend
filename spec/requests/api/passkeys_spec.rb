# frozen_string_literal: true

require "rails_helper"
require "webauthn/fake_client"

RSpec.describe "Api::Passkeys", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  ORIGIN = "http://localhost:3000"

  let(:user) { User.create!(email: "passkey@wit.edu", password: "password123", confirmed_at: Time.current) }
  let(:headers) { { "Authorization" => "Bearer #{JsonWebTokenService.encode(user_id: user.id)}" } }
  let(:authenticator) { WebAuthn::FakeAuthenticator.new }
  let(:client) { WebAuthn::FakeClient.new(ORIGIN, authenticator: authenticator) }

  def unrelated_challenge = SecureRandom.urlsafe_base64(32)

  before { Flipper.enable(FlipperFlags::V1) }

  after { Flipper.disable(FlipperFlags::V1) }

  def json = JSON.parse(response.body)

  # Runs the full registration ceremony and returns the stored passkey.
  def register(nickname: nil, as: headers, with: client)
    post "/api/user/passkeys/registration_options", headers: as
    handle    = json["handle"]
    challenge = json.dig("options", "challenge")

    credential = with.create(challenge: challenge)

    post "/api/user/passkeys",
         params:  { handle: handle, nickname: nickname, credential: credential },
         headers: as,
         as:      :json

    Passkey.find_by(external_id: credential["id"])
  end

  describe "registration" do
    it "refuses to hand out options without a token" do
      post "/api/user/passkeys/registration_options"

      expect(response).to have_http_status(:unauthorized)
    end

    it "stores a passkey for the signed-in user" do
      passkey = register(nickname: "Work laptop")

      expect(response).to have_http_status(:created)
      expect(passkey.user).to eq(user)
      expect(passkey.nickname).to eq("Work laptop")
      expect(json.dig("passkey", "nickname")).to eq("Work laptop")
    end

    it "names an unnamed passkey, and keeps the names apart" do
      register
      register(with: WebAuthn::FakeClient.new(ORIGIN))

      expect(user.passkeys.pluck(:nickname)).to contain_exactly("Passkey", "Passkey 2")
    end

    it "consumes the challenge, so the same one cannot register twice" do
      post "/api/user/passkeys/registration_options", headers: headers
      handle    = json["handle"]
      challenge = json.dig("options", "challenge")

      post "/api/user/passkeys",
           params: { handle: handle, credential: client.create(challenge: challenge) },
           headers: headers, as: :json
      expect(response).to have_http_status(:created)

      other = WebAuthn::FakeClient.new(ORIGIN)
      post "/api/user/passkeys",
           params: { handle: handle, credential: other.create(challenge: challenge) },
           headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.passkeys.count).to eq(1)
    end

    it "rejects a credential signed for a different challenge" do
      post "/api/user/passkeys/registration_options", headers: headers
      handle = json["handle"]

      post "/api/user/passkeys",
           params: { handle: handle, credential: client.create(challenge: unrelated_challenge) },
           headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.passkeys.count).to eq(0)
    end

    it "will not let one user register against another user's challenge" do
      post "/api/user/passkeys/registration_options", headers: headers
      handle    = json["handle"]
      challenge = json.dig("options", "challenge")

      intruder = User.create!(email: "intruder@wit.edu", password: "password123")
      intruder_headers = { "Authorization" => "Bearer #{JsonWebTokenService.encode(user_id: intruder.id)}" }

      post "/api/user/passkeys",
           params: { handle: handle, credential: client.create(challenge: challenge) },
           headers: intruder_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(intruder.passkeys.count).to eq(0)
    end
  end

  describe "sign-in" do
    it "returns a token for the passkey's owner" do
      passkey = register

      post "/api/user/passkeys/authentication_options"
      handle    = json["handle"]
      challenge = json.dig("options", "challenge")

      post "/api/user/passkeys/authenticate",
           params: { handle: handle, credential: client.get(challenge: challenge) },
           as:     :json

      expect(response).to have_http_status(:ok)
      expect(JsonWebTokenService.decode(json["jwt"])[:user_id]).to eq(user.id)
      expect(json["pub_id"]).to eq(user.public_id.delete_prefix("usr_"))
      expect(passkey.reload.last_used_at).to be_present
    end

    it "hands out options without a token, because sign-in has none yet" do
      post "/api/user/passkeys/authentication_options"

      expect(response).to have_http_status(:ok)
      expect(json["handle"]).to be_present
    end

    it "refuses a challenge that was already spent" do
      register

      post "/api/user/passkeys/authentication_options"
      handle    = json["handle"]
      challenge = json.dig("options", "challenge")

      post "/api/user/passkeys/authenticate",
           params: { handle: handle, credential: client.get(challenge: challenge) }, as: :json
      expect(response).to have_http_status(:ok)

      post "/api/user/passkeys/authenticate",
           params: { handle: handle, credential: client.get(challenge: challenge) }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a credential this backend never registered" do
      post "/api/user/passkeys/authentication_options"
      handle    = json["handle"]
      challenge = json.dig("options", "challenge")

      stranger = WebAuthn::FakeClient.new(ORIGIN)
      stranger.create(challenge: unrelated_challenge)

      post "/api/user/passkeys/authenticate",
           params: { handle: handle, credential: stranger.get(challenge: challenge) }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a ceremony run from an origin we do not allow" do
      register

      post "/api/user/passkeys/authentication_options"
      handle    = json["handle"]
      challenge = json.dig("options", "challenge")

      # Same authenticator and same relying party, but the page driving the
      # ceremony sits on another origin — which is the shape of a phishing site.
      elsewhere = WebAuthn::FakeClient.new("http://evil.example.com", authenticator: authenticator)

      post "/api/user/passkeys/authenticate",
           params: { handle: handle, credential: elsewhere.get(challenge: challenge, rp_id: "localhost") },
           as:     :json

      expect(response).to have_http_status(:unauthorized)
    end

    it "expires a challenge that sat unused" do
      register

      post "/api/user/passkeys/authentication_options"
      handle    = json["handle"]
      challenge = json.dig("options", "challenge")

      travel(WebauthnChallenge::TTL + 1.minute) do
        post "/api/user/passkeys/authenticate",
             params: { handle: handle, credential: client.get(challenge: challenge) }, as: :json
      end

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "managing passkeys" do
    it "lists only the signed-in user's passkeys" do
      register(nickname: "Mine")

      other = User.create!(email: "other@wit.edu", password: "password123")
      other.passkeys.create!(external_id: "someone-else", public_key: "key", nickname: "Theirs")

      get "/api/user/passkeys", headers: headers

      expect(json["passkeys"].map { |p| p["nickname"] }).to eq([ "Mine" ])
    end

    it "removes a passkey the user owns" do
      passkey = register

      delete "/api/user/passkeys/#{passkey.public_id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(Passkey.exists?(passkey.id)).to be(false)
    end

    it "will not remove someone else's passkey" do
      other = User.create!(email: "other@wit.edu", password: "password123")
      theirs = other.passkeys.create!(external_id: "someone-else", public_key: "key", nickname: "Theirs")

      delete "/api/user/passkeys/#{theirs.public_id}", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(Passkey.exists?(theirs.id)).to be(true)
    end

    it "goes with the account when the account goes" do
      register

      expect { user.destroy! }.to change(Passkey, :count).by(-1)
    end
  end
end
