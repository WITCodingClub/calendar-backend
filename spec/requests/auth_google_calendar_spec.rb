# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Adding a Google account to a user", type: :request do
  let(:user)         { create(:user) }
  let(:chosen_email) { "other.account@example.com" }
  let(:uid)          { "google-uid-add-account" }
  let(:service)      { instance_double(GoogleCalendarService, create_or_get_course_calendar: "cal-123") }
  let(:success_url)  { "/oauth/success?email=#{CGI.escape(chosen_email)}&calendar_id=cal-123" }

  # The test environment uses a null cache store. The state nonce and the
  # pending link live in Rails.cache, so these examples need a real store.
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(cache)
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

  def failure_message
    CGI.unescape(response.location.to_s)
  end

  context "when the browser is signed in as the same user (dashboard)" do
    let(:state) { GoogleSignIn::OauthState.generate_state(user_id: user.id) }

    before { sign_in user }

    it "links any Google account the person picks" do
      get "/auth/google_oauth2/callback", params: { state: state }

      credential = user.oauth_credentials.find_by!(provider: "google", email: chosen_email)
      expect(credential).to have_attributes(uid: uid, access_token: "new-access-token", refresh_token: "new-refresh-token")
      expect(response).to redirect_to(success_url)
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
      expect(failure_message).to include("already connected to another user")
    end

    it "fails with a clear message when the account's new email is on another credential of the user" do
      create(:oauth_credential, user: user, email: "old.address@example.com", uid: uid)
      create(:oauth_credential, user: user, email: chosen_email, uid: "a-different-uid")

      get "/auth/google_oauth2/callback", params: { state: state }

      expect(response.location).to include("/oauth/failure")
      expect(failure_message).to include("Another connected Google account already uses #{chosen_email}")
    end
  end

  context "when the browser is signed in as a different user" do
    it "links nothing" do
      sign_in create(:user)
      state = GoogleSignIn::OauthState.generate_state(user_id: user.id)

      get "/auth/google_oauth2/callback", params: { state: state }

      expect(OauthCredential.count).to eq(0)
      expect(response.location).to include("/oauth/failure")
      expect(failure_message).to include("signed in as a different user")
    end
  end

  context "when the browser has no session (extension)" do
    let(:state) { GoogleSignIn::OauthState.generate_state(user_id: user.id) }

    it "asks the person to confirm before it saves tokens" do
      get "/auth/google_oauth2/callback", params: { state: state }

      expect(response).to redirect_to(oauth_confirm_path)
      expect(OauthCredential.count).to eq(0)

      get oauth_confirm_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(chosen_email, user.email)
    end

    it "links the account after the person confirms" do
      get "/auth/google_oauth2/callback", params: { state: state }
      post oauth_confirm_path

      credential = user.oauth_credentials.find_by!(provider: "google", email: chosen_email)
      expect(credential).to have_attributes(uid: uid, access_token: "new-access-token", refresh_token: "new-refresh-token")
      expect(response).to redirect_to(success_url)
    end

    it "links nothing when the person cancels" do
      get "/auth/google_oauth2/callback", params: { state: state }
      delete oauth_confirm_path

      expect(OauthCredential.count).to eq(0)
      expect(response.location).to include("/oauth/failure")

      post oauth_confirm_path
      expect(OauthCredential.count).to eq(0)
    end

    it "links nothing on a confirm from a browser that did not finish the sign-in" do
      post oauth_confirm_path

      expect(OauthCredential.count).to eq(0)
      expect(response.location).to include("/oauth/failure")
    end

    it "rejects a confirm without a CSRF token" do
      get "/auth/google_oauth2/callback", params: { state: state }

      ActionController::Base.allow_forgery_protection = true
      begin
        post oauth_confirm_path
      ensure
        ActionController::Base.allow_forgery_protection = false
      end

      expect(OauthCredential.count).to eq(0)
    end

    it "does not offer an account that belongs to another user" do
      create(:oauth_credential, email: chosen_email, uid: uid)

      get "/auth/google_oauth2/callback", params: { state: state }

      expect(response.location).to include("/oauth/failure")
      expect(failure_message).to include("already connected to another user")
    end
  end

  describe "the state" do
    before { sign_in user }

    it "works only once" do
      state = GoogleSignIn::OauthState.generate_state(user_id: user.id)
      get "/auth/google_oauth2/callback", params: { state: state }
      user.oauth_credentials.destroy_all

      get "/auth/google_oauth2/callback", params: { state: state }

      expect(user.oauth_credentials.reload).to be_empty
      expect(response.location).to include("/oauth/failure")
    end

    it "must come from this flow" do
      state = MicrosoftGraph::OauthState.generate(user_id: user.id)

      get "/auth/google_oauth2/callback", params: { state: state }

      expect(user.oauth_credentials).to be_empty
    end
  end

  context "when the state has an email (old extension builds)" do
    before { sign_in user }

    it "links the account when the picked account matches" do
      state = GoogleSignIn::OauthState.generate_state(user_id: user.id, email: chosen_email)

      get "/auth/google_oauth2/callback", params: { state: state }

      expect(user.oauth_credentials.find_by(provider: "google", email: chosen_email)).to be_present
      expect(response.location).to start_with("http://www.example.com/oauth/success")
    end

    it "rejects a different account" do
      state = GoogleSignIn::OauthState.generate_state(user_id: user.id, email: "expected@example.com")

      get "/auth/google_oauth2/callback", params: { state: state }

      expect(user.oauth_credentials).to be_empty
      expect(response.location).to include("/oauth/failure")
    end
  end
end
