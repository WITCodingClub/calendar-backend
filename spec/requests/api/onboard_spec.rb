# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Users onboarding", type: :request do
  before { Flipper.enable(FlipperFlags::V1) }

  after { Flipper.disable(FlipperFlags::V1) }

  def json = JSON.parse(response.body)

  def verification(email:, verified: true, success: true, error: nil)
    GoogleTokenVerifier::Result.new(
      success: success, email: email, email_verified: verified, error: error
    )
  end

  def stub_google(result)
    allow(GoogleTokenVerifier).to receive(:verify_access_token).and_return(result)
  end

  describe "POST /api/user/onboard" do
    it "refuses a request that carries no token" do
      post "/api/user/onboard", params: { preferred_name: "Ada Lovelace" }

      expect(response).to have_http_status(:bad_request)
    end

    it "refuses a token Google does not accept" do
      stub_google(verification(email: nil, success: false, error: "token rejected by Google"))

      post "/api/user/onboard", params: { google_access_token: "bad-token" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "creates the account from the Google-verified WIT address" do
      stub_google(verification(email: "lovelacea@wit.edu"))

      post "/api/user/onboard",
           params: { google_access_token: "good-token", preferred_name: "Ada Lovelace" }

      expect(response).to have_http_status(:ok)

      user = User.find_by(email: "lovelacea@wit.edu")
      expect(user.first_name).to eq("Ada")
      expect(user.last_name).to eq("Lovelace")
      expect(json["pub_id"]).to eq(user.public_id.delete_prefix("usr_"))
    end

    it "returns the existing account rather than a second one" do
      existing = User.create!(email: "hoppeg@wit.edu", password: "password123", first_name: "Grace")
      stub_google(verification(email: "hoppeg@wit.edu"))

      expect {
        post "/api/user/onboard", params: { google_access_token: "good-token" }
      }.not_to change(User, :count)

      expect(JsonWebTokenService.decode(json["jwt"])[:user_id]).to eq(existing.id)
    end

    it "refuses a personal Google account, and says to use the WIT one" do
      stub_google(verification(email: "ada@gmail.com"))

      post "/api/user/onboard", params: { google_access_token: "personal-token" }

      expect(response).to have_http_status(:forbidden)
      expect(json["code"]).to eq("WIT_ACCOUNT_REQUIRED")
      expect(User.count).to eq(0)
    end

    it "refuses an address Google has not verified" do
      stub_google(verification(email: "lovelacea@wit.edu", verified: false))

      post "/api/user/onboard", params: { google_access_token: "unverified-token" }

      expect(response).to have_http_status(:forbidden)
      expect(User.count).to eq(0)
    end

    it "does not reach a WIT account through a personal address linked for calendar sync" do
      owner = User.create!(email: "hoppeg@wit.edu", password: "password123")
      owner.oauth_credentials.create!(
        provider: "google", email: "grace@gmail.com", uid: "google-uid-1",
        access_token: "token", refresh_token: "refresh", token_expires_at: 1.hour.from_now
      )
      stub_google(verification(email: "grace@gmail.com"))

      post "/api/user/onboard", params: { google_access_token: "personal-token" }

      expect(response).to have_http_status(:forbidden)
      expect(owner.reload.email).to eq("hoppeg@wit.edu")
    end

    it "issues a token that expires" do
      stub_google(verification(email: "lovelacea@wit.edu"))

      post "/api/user/onboard", params: { google_access_token: "good-token" }

      expect(JsonWebTokenService.decode(json["jwt"])[:exp]).to be_present
    end
  end
end
