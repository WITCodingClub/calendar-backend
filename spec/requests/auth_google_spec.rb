# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Signing in to the dashboard with Google", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:email) { "webui@wit.edu" }

  before do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider:    "google_oauth2",
      uid:         "google-uid-123",
      info:        { email: email, first_name: "Web", last_name: "User" },
      credentials: { token: "access-token", expires_at: 1.hour.from_now.to_i },
      extra:       { raw_info: { granted_scopes: "email profile" } }
    )
  end

  after do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  it "sets a remember cookie" do
    get "/auth/google_oauth2/callback"

    expect(response).to redirect_to(dashboard_root_path)
    expect(cookies["remember_user_token"]).to be_present
  end

  it "keeps the person signed in after the idle timeout" do
    get "/auth/google_oauth2/callback"

    travel(User.timeout_in + 1.minute) do
      get dashboard_settings_path
      expect(response).to have_http_status(:ok)
    end
  end

  it "asks the person to sign in again once the remember period ends" do
    get "/auth/google_oauth2/callback"

    travel(User.remember_for + 1.day) do
      # A timed-out GET is sent back to the page it asked for, signed out.
      get dashboard_root_path
      follow_redirect! while response.redirect? && URI(response.location).path != new_user_session_path

      expect(response).to be_redirect
      expect(URI(response.location).path).to eq(new_user_session_path)
    end
  end
  context "when calendar scopes are granted and the Google account is on another user" do
    before do
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider:    "google_oauth2",
        uid:         "google-uid-123",
        info:        { email: email, first_name: "Web", last_name: "User" },
        credentials: { token: "access-token", expires_at: 1.hour.from_now.to_i },
        extra:       { raw_info: { granted_scopes: "email profile calendar" } }
      )
    end

    it "signs the person in and keeps the other user's credential" do
      other = create(:oauth_credential, uid: "google-uid-123")

      get "/auth/google_oauth2/callback"

      expect(response).to redirect_to(dashboard_root_path)
      expect(flash[:alert]).to include("connected to another user")
      expect(other.reload.access_token).to eq("factory-access-token")
      expect(User.find_by(email: email).oauth_credentials).to be_empty
    end
  end
end
