# frozen_string_literal: true

require "rails_helper"
require "webauthn/fake_client"

RSpec.describe "Signing in to the dashboard with a passkey", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(email: "webui@wit.edu", password: "password123", confirmed_at: Time.current) }
  let(:client) { WebAuthn::FakeClient.new("http://localhost:3000") }

  def json = JSON.parse(response.body)

  # Registers a credential the way the API does, so sign-in has something real.
  def register_passkey(for_user: user, with: client)
    token = api_token_for(for_user)
    post "/api/user/passkeys/registration_options", headers: { "Authorization" => "Bearer #{token}" }
    handle    = json["handle"]
    challenge = json.dig("options", "challenge")
    post "/api/user/passkeys",
         params:  { handle: handle, credential: with.create(challenge: challenge) },
         headers: { "Authorization" => "Bearer #{token}" },
         as:      :json
    for_user.passkeys.last
  end

  before { Flipper.enable(FlipperFlags::V1) }

  after { Flipper.disable(FlipperFlags::V1) }

  it "offers the passkey button on the sign-in page" do
    get "/users/sign_in"

    expect(response.body).to include("Sign in with a passkey")
  end

  it "signs the person in and sends them where they belong" do
    passkey = register_passkey

    post "/users/passkey/options"
    expect(response).to have_http_status(:ok)
    handle    = json["handle"]
    challenge = json.dig("options", "challenge")

    post "/users/passkey/callback",
         params: { handle: handle, credential: client.get(challenge: challenge) },
         as:     :json

    expect(response).to have_http_status(:ok)
    expect(json["redirect_to"]).to be_present
    expect(passkey.reload.last_used_at).to be_present

    # The session is a real one: a page behind authentication now opens.
    get json["redirect_to"]
    expect(response).not_to redirect_to(new_user_session_path)
  end

  it "remembers the person past the idle timeout" do
    register_passkey

    post "/users/passkey/options"
    handle    = json["handle"]
    challenge = json.dig("options", "challenge")

    post "/users/passkey/callback",
         params: { handle: handle, credential: client.get(challenge: challenge) }, as: :json
    expect(cookies["remember_user_token"]).to be_present
    redirect_path = json["redirect_to"]

    travel(User.timeout_in + 1.minute) do
      get redirect_path
      expect(response).to have_http_status(:ok)
    end
  end

  it "refuses a challenge that was already spent" do
    register_passkey

    post "/users/passkey/options"
    handle    = json["handle"]
    challenge = json.dig("options", "challenge")

    post "/users/passkey/callback",
         params: { handle: handle, credential: client.get(challenge: challenge) }, as: :json
    expect(response).to have_http_status(:ok)

    post "/users/passkey/callback",
         params: { handle: handle, credential: client.get(challenge: challenge) }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it "refuses a credential this site never registered" do
    post "/users/passkey/options"
    handle    = json["handle"]
    challenge = json.dig("options", "challenge")

    stranger = WebAuthn::FakeClient.new("http://localhost:3000")
    stranger.create(challenge: SecureRandom.urlsafe_base64(32))

    post "/users/passkey/callback",
         params: { handle: handle, credential: stranger.get(challenge: challenge) }, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it "refuses a ceremony run from an origin we do not allow" do
    authenticator = WebAuthn::FakeAuthenticator.new
    here = WebAuthn::FakeClient.new("http://localhost:3000", authenticator: authenticator)
    register_passkey(with: here)

    post "/users/passkey/options"
    handle    = json["handle"]
    challenge = json.dig("options", "challenge")

    elsewhere = WebAuthn::FakeClient.new("http://evil.example.com", authenticator: authenticator)
    post "/users/passkey/callback",
         params: { handle: handle, credential: elsewhere.get(challenge: challenge, rp_id: "localhost") },
         as:     :json

    expect(response).to have_http_status(:unauthorized)
  end

  it "creates no account — a passkey only opens one that already exists" do
    post "/users/passkey/options"
    handle    = json["handle"]
    challenge = json.dig("options", "challenge")
    unknown = WebAuthn::FakeClient.new("http://localhost:3000")
    unknown.create(challenge: SecureRandom.urlsafe_base64(32))

    expect {
      post "/users/passkey/callback",
           params: { handle: handle, credential: unknown.get(challenge: challenge) }, as: :json
    }.not_to change(User, :count)
  end
end
