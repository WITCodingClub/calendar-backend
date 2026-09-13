require "rails_helper"
require "webauthn/fake_client"

RSpec.describe "sign count behaviour", type: :request do
  let(:user) { User.create!(email: "sc@wit.edu", password: "password123", confirmed_at: Time.current) }
  let(:headers) { { "Authorization" => "Bearer #{JsonWebTokenService.encode(user_id: user.id)}" } }
  let(:client) { WebAuthn::FakeClient.new("http://localhost:3000") }
  def json = JSON.parse(response.body)

  before { Flipper.enable(FlipperFlags::V1) }
  after  { Flipper.disable(FlipperFlags::V1) }

  it "records a use even when the authenticator never increments its counter" do
    post "/api/user/passkeys/handoff", headers: headers
    code = json["code"]
    post "/api/user/passkeys/registration_options", params: { handoff: code }
    handle, challenge = json["handle"], json.dig("options", "challenge")
    post "/api/user/passkeys", params: { handle: handle, handoff: code, credential: client.create(challenge: challenge) }, as: :json

    passkey = user.passkeys.sole
    expect(passkey.sign_count).to eq(0)
    expect(passkey.last_used_at).to be_nil

    post "/api/user/passkeys/authentication_options"
    handle, challenge = json["handle"], json.dig("options", "challenge")
    # sign_count: 0 is what a platform authenticator reports every time.
    post "/api/user/passkeys/authenticate",
         params: { handle: handle, handoff: true, credential: client.get(challenge: challenge, sign_count: 0) },
         as: :json

    expect(response).to have_http_status(:ok)
    passkey.reload
    expect(passkey.sign_count).to eq(0)
    expect(passkey.last_used_at).to be_present
  end
end
