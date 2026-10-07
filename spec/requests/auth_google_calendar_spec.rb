# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Adding a Google account to a user", type: :request do
  let(:user)         { create(:user) }
  let(:chosen_email) { "other.account@example.com" }
  let(:uid)          { "google-uid-add-account" }
  let(:service)      { instance_double(GoogleCalendarService, create_or_get_course_calendar: "cal-123") }

  before do
    allow(GoogleCalendarService).to receive(:new).with(user).and_return(service)
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider:    "google_oauth2",
      uid:         uid,
      info:        { email: chosen_email, first_name: "Other", last_name: "Account" },
      credentials: { token: "new-access-token", refresh_token: "new-refresh-token", expires_at: 1.hour.from_now.to_i },
      extra:       { raw_info: { granted_scopes: "email profile calendar" } }
    )
  end

  after do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  context "when the state has no email" do
    let(:state) { GoogleOauthStateService.generate_state(user_id: user.id) }

    it "links any Google account the person picks" do
      get "/auth/google_oauth2/callback", params: { state: state }

      credential = user.oauth_credentials.find_by!(provider: "google", email: chosen_email)
      expect(credential).to have_attributes(uid: uid, access_token: "new-access-token", refresh_token: "new-refresh-token")
      expect(response).to redirect_to("/oauth/success?email=#{CGI.escape(chosen_email)}&calendar_id=cal-123")
    end

    it "updates the tokens when the account is already linked to the same user" do
      existing = create(:oauth_credential, user: user, email: chosen_email, uid: uid, access_token: "old")

      expect { get "/auth/google_oauth2/callback", params: { state: state } }
        .not_to change(OauthCredential, :count)

      expect(existing.reload.access_token).to eq("new-access-token")
    end

    it "does not link a Google account that belongs to another user" do
      create(:oauth_credential, email: chosen_email, uid: uid)

      expect { get "/auth/google_oauth2/callback", params: { state: state } }
        .not_to change(OauthCredential, :count)

      expect(user.oauth_credentials).to be_empty
      expect(response.location).to include("/oauth/failure")
      expect(CGI.unescape(response.location)).to include("already connected to another user")
    end
  end

  context "when the state has an email (old extension builds)" do
    it "links the account when the picked account matches" do
      state = GoogleOauthStateService.generate_state(user_id: user.id, email: chosen_email)

      get "/auth/google_oauth2/callback", params: { state: state }

      expect(user.oauth_credentials.find_by(provider: "google", email: chosen_email)).to be_present
      expect(response.location).to start_with("http://www.example.com/oauth/success")
    end

    it "rejects a different account" do
      state = GoogleOauthStateService.generate_state(user_id: user.id, email: "expected@example.com")

      get "/auth/google_oauth2/callback", params: { state: state }

      expect(user.oauth_credentials).to be_empty
      expect(response.location).to include("/oauth/failure")
    end
  end
end
