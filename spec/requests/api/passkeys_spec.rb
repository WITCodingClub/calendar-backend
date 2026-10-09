# frozen_string_literal: true

require "rails_helper"
require "webauthn/fake_client"

RSpec.describe "Api::Passkeys", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  ORIGIN = "http://localhost:3000"

  let(:user) { create(:user) }
  let(:headers) { { "Authorization" => "Bearer #{api_token_for(user)}" } }
  let(:authenticator) { WebAuthn::FakeAuthenticator.new }
  let(:client) { WebAuthn::FakeClient.new(ORIGIN, authenticator: authenticator) }

  def unrelated_challenge = SecureRandom.urlsafe_base64(32)

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

    it "keeps counting past the second unnamed passkey" do
      3.times { register(with: WebAuthn::FakeClient.new(ORIGIN)) }

      expect(user.passkeys.pluck(:nickname)).to contain_exactly("Passkey", "Passkey 2", "Passkey 3")
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

      intruder = create(:user)
      intruder_headers = { "Authorization" => "Bearer #{api_token_for(intruder)}" }

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

      other = create(:user)
      create(:passkey, user: other, nickname: "Theirs")

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
      other = create(:user)
      theirs = create(:passkey, user: other, nickname: "Theirs")

      delete "/api/user/passkeys/#{theirs.public_id}", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(Passkey.exists?(theirs.id)).to be(true)
    end

    it "goes with the account when the account goes" do
      register

      expect { user.destroy! }.to change(Passkey, :count).by(-1)
    end

    it "refuses to list passkeys without a token" do
      get "/api/user/passkeys"

      expect(response).to have_http_status(:unauthorized)
    end

    it "lists an empty array for a user with no passkeys" do
      get "/api/user/passkeys", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("passkeys" => [])
    end

    it "lists the most recently used passkey first and shows its fields" do
      older = create(:passkey, user: user, nickname: "Older", last_used_at: 3.days.ago)
      newer = create(:passkey, user: user, nickname: "Newer", last_used_at: 1.hour.ago)
      unused = create(:passkey, user: user, nickname: "Unused", last_used_at: nil)

      get "/api/user/passkeys", headers: headers

      expect(json["passkeys"].pluck("id")).to eq([ newer, older, unused ].map(&:public_id))
      expect(json["passkeys"].first.keys).to contain_exactly("id", "nickname", "created_at", "last_used_at")
      expect(json["passkeys"].last["last_used_at"]).to be_nil
    end

    it "refuses to remove a passkey without a token" do
      passkey = create(:passkey, user: user)

      delete "/api/user/passkeys/#{passkey.public_id}"

      expect(response).to have_http_status(:unauthorized)
      expect(Passkey.exists?(passkey.id)).to be(true)
    end

    it "answers not found for a passkey that does not exist" do
      delete "/api/user/passkeys/pky_doesnotexist", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(json).to include("error" => "Passkey not found")
    end

    it "removes a passkey by its numeric id" do
      passkey = create(:passkey, user: user)

      delete "/api/user/passkeys/#{passkey.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("message" => "Passkey removed")
      expect(Passkey.exists?(passkey.id)).to be(false)
    end

    it "revokes the sessions that the removed passkey opened" do
      passkey = register
      post "/api/user/passkeys/authentication_options"
      post "/api/user/passkeys/authenticate",
           params: { handle: json["handle"], credential: client.get(challenge: json.dig("options", "challenge")) },
           as:     :json
      session_record = UserSession.find_by!(passkey_id: passkey.id)

      delete "/api/user/passkeys/#{passkey.public_id}", headers: headers

      expect(session_record.reload).to have_attributes(passkey_id: nil, revoked_reason: "passkey removed")
      expect(session_record.revoked_at).to be_present
    end
  end

  describe "registration options" do
    it "describes the user and excludes credentials the account already holds" do
      existing = create(:passkey, user: user)
      create(:passkey, user: create(:user))

      post "/api/user/passkeys/registration_options", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json.dig("options", "user", "name")).to eq(user.email)
      expect(json.dig("options", "excludeCredentials").pluck("id")).to eq([ existing.external_id ])
      expect(WebauthnChallenge.find_by!(handle: json["handle"])).to have_attributes(purpose: "registration", user: user)
    end

    it "falls back to the email when the user has no name" do
      user.update!(first_name: nil, last_name: nil)

      post "/api/user/passkeys/registration_options", headers: headers

      expect(json.dig("options", "user", "displayName")).to eq(user.email)
    end
  end

  describe "registration errors" do
    it "refuses to store a passkey without a token" do
      post "/api/user/passkeys", params: { handle: "anything" }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a handle that was never issued" do
      post "/api/user/passkeys",
           params: { handle: "never-issued", credential: client.create(challenge: unrelated_challenge) },
           headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("Passkey registration expired. Start again.")
    end

    it "rejects a missing handle" do
      post "/api/user/passkeys",
           params: { credential: client.create(challenge: unrelated_challenge) },
           headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects a handle from the sign-in flow" do
      post "/api/user/passkeys/authentication_options"
      handle    = json["handle"]
      challenge = json.dig("options", "challenge")

      post "/api/user/passkeys",
           params: { handle: handle, credential: client.create(challenge: challenge) },
           headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.passkeys.count).to eq(0)
    end

    it "rejects a registration challenge that expired" do
      post "/api/user/passkeys/registration_options", headers: headers
      handle    = json["handle"]
      challenge = json.dig("options", "challenge")

      travel(WebauthnChallenge::TTL + 1.minute) do
        post "/api/user/passkeys",
             params: { handle: handle, credential: client.create(challenge: challenge) },
             headers: headers, as: :json
      end

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "answers bad request when the credential is missing" do
      post "/api/user/passkeys/registration_options", headers: headers

      post "/api/user/passkeys", params: { handle: json["handle"] }, headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "rejects a credential that is not a valid attestation" do
      post "/api/user/passkeys/registration_options", headers: headers

      post "/api/user/passkeys",
           params: { handle: json["handle"], credential: { type: "public-key", id: "abc", rawId: "abc",
                                                           response: { attestationObject: "bad", clientDataJSON: "bad" } } },
           headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("Could not verify this passkey")
    end

    it "answers bad request when the credential has no response" do
      post "/api/user/passkeys/registration_options", headers: headers

      post "/api/user/passkeys",
           params: { handle: json["handle"], credential: { type: "public-key", id: "abc", rawId: "abc" } },
           headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "rejects a nickname the user already uses" do
      register(nickname: "Laptop")
      expect(response).to have_http_status(:created)

      register(nickname: "laptop", with: WebAuthn::FakeClient.new(ORIGIN))

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.passkeys.count).to eq(1)
    end

    it "rejects a credential that is already registered" do
      register
      duplicate = Passkey.last

      post "/api/user/passkeys/registration_options", headers: headers
      credential = client.create(challenge: json.dig("options", "challenge"))
      credential["id"] = duplicate.external_id
      credential["rawId"] = duplicate.external_id
      post "/api/user/passkeys", params: { handle: json["handle"], credential: credential }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "trims the nickname" do
      passkey = register(nickname: "  Desk key  ")

      expect(passkey.nickname).to eq("Desk key")
    end
  end

  describe "sign-in errors" do
    it "rejects a missing or unknown handle" do
      register

      post "/api/user/passkeys/authenticate", params: { credential: client.get(challenge: unrelated_challenge) }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(json["error"]).to eq("Sign-in expired. Start again.")

      post "/api/user/passkeys/authenticate",
           params: { handle: "never-issued", credential: client.get(challenge: unrelated_challenge) }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a credential that is not valid base64" do
      post "/api/user/passkeys/authentication_options"

      post "/api/user/passkeys/authenticate",
           params: { handle: json["handle"], credential: { type: "public-key", id: "abc", rawId: "abc",
                                                           response: { authenticatorData: "bad", clientDataJSON: "bad", signature: "bad" } } },
           as:     :json

      expect(response).to have_http_status(:unauthorized)
      expect(json["error"]).to eq("Could not verify this passkey")
    end

    it "answers bad request when the credential has no response" do
      post "/api/user/passkeys/authentication_options"

      post "/api/user/passkeys/authenticate",
           params: { handle: json["handle"], credential: { type: "public-key", id: "abc", rawId: "abc" } },
           as:     :json

      expect(response).to have_http_status(:bad_request)
    end

    it "rejects a registration handle used for sign-in" do
      register
      post "/api/user/passkeys/registration_options", headers: headers

      post "/api/user/passkeys/authenticate",
           params: { handle: json["handle"], credential: client.get(challenge: json.dig("options", "challenge")) },
           as:     :json

      expect(response).to have_http_status(:unauthorized)
    end

    it "names an unknown passkey in the error" do
      post "/api/user/passkeys/authentication_options"
      handle    = json["handle"]
      challenge = json.dig("options", "challenge")
      stranger  = WebAuthn::FakeClient.new(ORIGIN)
      stranger.create(challenge: unrelated_challenge)

      post "/api/user/passkeys/authenticate",
           params: { handle: handle, credential: stranger.get(challenge: challenge) }, as: :json

      expect(json["error"]).to eq("Unknown passkey")
    end

    it "answers bad request when the credential is missing" do
      post "/api/user/passkeys/authentication_options"

      post "/api/user/passkeys/authenticate", params: { handle: json["handle"] }, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "rejects an assertion signed for another challenge" do
      register

      post "/api/user/passkeys/authentication_options"
      handle = json["handle"]

      post "/api/user/passkeys/authenticate",
           params: { handle: handle, credential: client.get(challenge: unrelated_challenge) }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json["error"]).to eq("Could not verify this passkey")
    end

    it "rejects a replayed assertion whose sign count did not advance" do
      passkey = register

      post "/api/user/passkeys/authentication_options"
      post "/api/user/passkeys/authenticate",
           params: { handle: json["handle"], credential: client.get(challenge: json.dig("options", "challenge"), sign_count: 10) },
           as:     :json
      expect(response).to have_http_status(:ok)
      expect(passkey.reload.sign_count).to eq(10)

      post "/api/user/passkeys/authentication_options"
      post "/api/user/passkeys/authenticate",
           params: { handle: json["handle"], credential: client.get(challenge: json.dig("options", "challenge"), sign_count: 5) },
           as:     :json

      expect(response).to have_http_status(:unauthorized)
      expect(passkey.reload.sign_count).to eq(10)
    end

    it "records the passkey on the session the token opens" do
      passkey = register

      post "/api/user/passkeys/authentication_options"
      post "/api/user/passkeys/authenticate",
           params: { handle: json["handle"], credential: client.get(challenge: json.dig("options", "challenge")) },
           as:     :json

      expect(UserSession.where(passkey_id: passkey.id)).to exist
    end
  end

  describe "handoff" do
    def handoff_code
      post "/api/user/passkeys/handoff", headers: headers
      json["code"]
    end

    it "refuses to mint a code without a token" do
      post "/api/user/passkeys/handoff"

      expect(response).to have_http_status(:unauthorized)
    end

    it "mints a single-use registration code for the signed-in user" do
      code = handoff_code

      expect(response).to have_http_status(:ok)
      expect(PasskeyHandoff.peek(code: code, purpose: "register")).to eq(user)
    end

    it "lets a page with no token register a passkey, then spends the code" do
      code = handoff_code

      post "/api/user/passkeys/registration_options", params: { handoff: code }
      expect(response).to have_http_status(:ok)
      handle    = json["handle"]
      challenge = json.dig("options", "challenge")

      post "/api/user/passkeys",
           params: { handle: handle, handoff: code, nickname: "Phone", credential: client.create(challenge: challenge) },
           as:     :json

      expect(response).to have_http_status(:created)
      expect(user.passkeys.pluck(:nickname)).to eq([ "Phone" ])
      expect(PasskeyHandoff.peek(code: code, purpose: "register")).to be_nil
    end

    it "keeps the code alive after a failed registration so the page can retry" do
      code = handoff_code
      post "/api/user/passkeys/registration_options", params: { handoff: code }

      post "/api/user/passkeys",
           params: { handle: json["handle"], handoff: code, credential: client.create(challenge: unrelated_challenge) },
           as:     :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(PasskeyHandoff.peek(code: code, purpose: "register")).to eq(user)
    end

    it "refuses an unknown code" do
      post "/api/user/passkeys/registration_options", params: { handoff: "unknown-code" }

      expect(response).to have_http_status(:unauthorized)
      expect(json["error"]).to eq("That registration link has expired. Start again.")
    end

    it "refuses an expired code" do
      code = handoff_code

      travel(PasskeyHandoff::TTL + 1.minute) do
        post "/api/user/passkeys/registration_options", params: { handoff: code }
      end

      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a session code in place of a registration code" do
      code = PasskeyHandoff.issue!(user: user, purpose: "session")

      post "/api/user/passkeys/registration_options", params: { handoff: code }

      expect(response).to have_http_status(:unauthorized)
    end

    it "does not use a registration code to reach the other endpoints" do
      get "/api/user/passkeys", params: { handoff: handoff_code }

      expect(response).to have_http_status(:unauthorized)
    end

    it "will not register against a challenge issued to another account" do
      other_code = PasskeyHandoff.issue!(user: create(:user), purpose: "register")
      post "/api/user/passkeys/registration_options", headers: headers
      handle    = json["handle"]
      challenge = json.dig("options", "challenge")

      post "/api/user/passkeys",
           params: { handle: handle, handoff: other_code, credential: client.create(challenge: challenge) },
           as:     :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(Passkey.count).to eq(0)
    end
  end

  describe "sign-in with a handoff" do
    def sign_in_params(**extra)
      post "/api/user/passkeys/authentication_options"
      { handle: json["handle"], credential: client.get(challenge: json.dig("options", "challenge")) }.merge(extra)
    end

    it "returns a code instead of a token when the page asks for one" do
      register

      post "/api/user/passkeys/authenticate", params: sign_in_params(handoff: true), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.keys).to eq([ "code" ])
      expect(PasskeyHandoff.peek(code: json["code"], purpose: "session")).to eq(user)
    end

    it "trades the code for a token exactly once" do
      register
      post "/api/user/passkeys/authenticate", params: sign_in_params(handoff: "true"), as: :json
      code = json["code"]

      post "/api/user/passkeys/exchange", params: { code: code }, as: :json

      expect(response).to have_http_status(:ok)
      expect(JsonWebTokenService.decode(json["jwt"])[:user_id]).to eq(user.id)
      expect(json["pub_id"]).to eq(user.public_id.delete_prefix("usr_"))

      post "/api/user/passkeys/exchange", params: { code: code }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns a token when the handoff flag is false" do
      register

      post "/api/user/passkeys/authenticate", params: sign_in_params(handoff: "false"), as: :json

      expect(json).to include("jwt")
    end

    it "refuses an unknown or missing code" do
      post "/api/user/passkeys/exchange", params: { code: "unknown-code" }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(json["error"]).to eq("That sign-in link has expired. Start again.")

      post "/api/user/passkeys/exchange", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a registration code and an expired code" do
      register_code = PasskeyHandoff.issue!(user: user, purpose: "register")
      post "/api/user/passkeys/exchange", params: { code: register_code }, as: :json
      expect(response).to have_http_status(:unauthorized)

      session_code = PasskeyHandoff.issue!(user: user, purpose: "session")
      travel(PasskeyHandoff::TTL + 1.minute) do
        post "/api/user/passkeys/exchange", params: { code: session_code }, as: :json
      end
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
