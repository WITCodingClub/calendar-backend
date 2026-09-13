# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Sessions", type: :request do
  let(:user) { User.create!(email: "sessions@wit.edu", password: "password123", confirmed_at: Time.current) }
  let(:token) { api_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }

  before { Flipper.enable(FlipperFlags::V1) }

  after { Flipper.disable(FlipperFlags::V1) }

  def json = JSON.parse(response.body)
  def session_for(raw) = UserSession.find_by(jti: JsonWebTokenService.decode(raw)[:jti])

  describe "a token without a session" do
    it "is refused, because nothing could ever revoke it" do
      orphan = JsonWebTokenService.encode({ user_id: user.id })

      get "/api/user/sessions", headers: { "Authorization" => "Bearer #{orphan}" }

      expect(response).to have_http_status(:unauthorized)
      expect(json["code"]).to eq("AUTH_REVOKED")
    end
  end

  describe "GET /api/user/sessions" do
    it "lists where the account is signed in, and marks the one asking" do
      other = api_token_for(user)

      get "/api/user/sessions", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json["sessions"].length).to eq(2)
      current = json["sessions"].find { |s| s["current"] }
      expect(current["id"]).to eq(session_for(token).public_id)
      expect(json["sessions"].map { |s| s["id"] }).to include(session_for(other).public_id)
    end

    it "shows nobody else's sessions" do
      stranger = User.create!(email: "stranger@wit.edu", password: "password123")
      api_token_for(stranger)

      get "/api/user/sessions", headers: headers

      expect(json["sessions"].length).to eq(1)
    end

    it "leaves out sessions that were already ended" do
      spent = api_token_for(user)
      session_for(spent).revoke!

      get "/api/user/sessions", headers: headers

      expect(json["sessions"].length).to eq(1)
    end

    it "records the device, so a person can tell their sessions apart" do
      get "/api/user/sessions", headers: headers.merge(
        "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/140.0.0.0 Safari/537.36"
      )

      expect(json["sessions"].first["device"]).to be_present
    end
  end

  describe "ending a session" do
    it "stops the revoked token working" do
      doomed = api_token_for(user)

      delete "/api/user/sessions/#{session_for(doomed).public_id}", headers: headers
      expect(response).to have_http_status(:ok)

      get "/api/user/sessions", headers: { "Authorization" => "Bearer #{doomed}" }
      expect(response).to have_http_status(:unauthorized)
      expect(json["code"]).to eq("AUTH_REVOKED")
    end

    it "will not end someone else's session" do
      stranger = User.create!(email: "stranger@wit.edu", password: "password123")
      theirs = session_for(api_token_for(stranger))

      delete "/api/user/sessions/#{theirs.public_id}", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(theirs.reload).to be_active
    end

    it "ends every other session but keeps the one asking" do
      elsewhere = api_token_for(user)

      post "/api/user/sessions/revoke_all", headers: headers

      expect(response).to have_http_status(:ok)
      expect(session_for(elsewhere).reload).to be_revoked
      expect(session_for(token).reload).to be_active
    end

    it "can end the asking session too, when told to" do
      post "/api/user/sessions/revoke_all", params: { keep_current: false }, headers: headers

      expect(session_for(token).reload).to be_revoked
    end
  end

  describe "sessions that a security event should end" do
    it "ends the sessions a removed passkey opened" do
      passkey = user.passkeys.create!(external_id: "cred-1", public_key: "key", nickname: "Old phone")
      from_passkey = JsonWebTokenService.issue(user: user, source: "passkey", passkey: passkey)
      unrelated    = api_token_for(user)

      passkey.destroy!

      expect(session_for(from_passkey).reload).to be_revoked
      expect(session_for(unrelated).reload).to be_active
    end

    it "ends every session when the Google account is disconnected" do
      signed_in = session_for(token) # the session must exist before the disconnect
      credential = user.oauth_credentials.create!(
        provider: "google", email: "them@gmail.com", uid: "uid-1",
        access_token: "t", refresh_token: "r", token_expires_at: 1.hour.from_now
      )

      credential.destroy!

      expect(signed_in.reload).to be_revoked
    end
  end

  describe "expiry" do
    it "stops honouring a session past its expiry, without anyone revoking it" do
      session_for(token).update!(expires_at: 1.minute.ago)

      get "/api/user/sessions", headers: headers

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
