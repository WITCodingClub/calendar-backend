# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin OAuth Authentication", type: :request do
  before :each do
    # Enable OmniAuth test mode
    OmniAuth.config.test_mode = true
    # Clear Rack::Attack cache to prevent rate limiting between tests
    Rack::Attack.cache.store.clear
  end

  after :each do
    # Reset OmniAuth test mode
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  describe "GET /auth/google_oauth2/callback" do
    let(:oauth_email) { "admin@wit.edu" }
    let(:oauth_data) do
      OmniAuth::AuthHash.new({
        provider: "google_oauth2",
        uid: "123456789",
        info: {
          email: oauth_email,
          first_name: "John",
          last_name: "Admin"
        },
        credentials: {
          token: "mock_access_token",
          refresh_token: "mock_refresh_token",
          expires_at: 1.hour.from_now.to_i
        }
      })
    end

    before do
      OmniAuth.config.mock_auth[:google_oauth2] = oauth_data
    end

    context "when user is an admin with primary email" do
      let!(:admin_user) do
        user = User.create!(access_level: :admin, first_name: "John", last_name: "Admin")
        user.emails.create!(email: "admin@wit.edu", primary: true)
        user
      end

      it "successfully signs in the user" do
        get "/auth/google_oauth2/callback"

        expect(response).to redirect_to(admin_root_path)
        expect(flash[:notice]).to eq("Successfully signed in with Google.")
        expect(session[:user_id]).to eq(admin_user.id)
      end

      it "creates OAuth credential for the user" do
        expect {
          get "/auth/google_oauth2/callback"
        }.to change { admin_user.oauth_credentials.count }.by(1)

        credential = admin_user.oauth_credentials.last
        expect(credential.provider).to eq("google")
        expect(credential.email).to eq("admin@wit.edu")
        expect(credential.uid).to eq("123456789")
      end

      it "updates existing OAuth credential if it exists" do
        admin_user.oauth_credentials.create!(
          provider: "google",
          email: "admin@wit.edu",
          uid: "old_uid",
          access_token: "old_token",
          refresh_token: "old_refresh_token"
        )

        expect {
          get "/auth/google_oauth2/callback"
        }.not_to change { admin_user.oauth_credentials.count }

        credential = admin_user.oauth_credentials.find_by(email: "admin@wit.edu")
        expect(credential.uid).to eq("123456789")
        expect(credential.access_token).not_to eq("old_token")
      end
    end

    context "when user is an admin with non-primary email" do
      let(:oauth_email) { "admin.secondary@wit.edu" }
      let!(:admin_user) do
        user = User.create!(access_level: :super_admin)
        user.emails.create!(email: "admin.primary@wit.edu", primary: true)
        user.emails.create!(email: "admin.secondary@wit.edu", primary: false)
        user
      end

      it "successfully signs in using non-primary email" do
        get "/auth/google_oauth2/callback"

        expect(response).to redirect_to(admin_root_path)
        expect(flash[:notice]).to eq("Successfully signed in with Google.")
        expect(session[:user_id]).to eq(admin_user.id)
      end

      it "creates OAuth credential for the non-primary email" do
        expect {
          get "/auth/google_oauth2/callback"
        }.to change { admin_user.oauth_credentials.count }.by(1)

        credential = admin_user.oauth_credentials.last
        expect(credential.email).to eq("admin.secondary@wit.edu")
      end
    end

    context "when user is an owner" do
      let(:oauth_email) { "owner@wit.edu" }
      let!(:owner_user) do
        user = User.create!(access_level: :owner)
        user.emails.create!(email: "owner@wit.edu", primary: true)
        user
      end

      it "successfully signs in the owner" do
        get "/auth/google_oauth2/callback"

        expect(response).to redirect_to(admin_root_path)
        expect(session[:user_id]).to eq(owner_user.id)
      end
    end

    context "when user exists but is not an admin" do
      let(:oauth_email) { "regular@wit.edu" }
      let!(:regular_user) do
        user = User.create!(access_level: :user)
        user.emails.create!(email: "regular@wit.edu", primary: true)
        user
      end

      it "rejects the sign-in" do
        get "/auth/google_oauth2/callback"

        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to eq("Sign-in is restricted to administrators only.")
        expect(session[:user_id]).to be_nil
      end
    end

    context "when user does not exist" do
      let(:oauth_email) { "nonexistent@wit.edu" }

      it "rejects the sign-in" do
        get "/auth/google_oauth2/callback"

        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to eq("Sign-in is restricted to administrators only.")
        expect(session[:user_id]).to be_nil
      end

      it "does not create a new user" do
        expect {
          get "/auth/google_oauth2/callback"
        }.not_to change { User.count }
      end
    end

    context "when email is not from @wit.edu domain" do
      let(:oauth_email) { "admin@gmail.com" }

      it "rejects the sign-in" do
        get "/auth/google_oauth2/callback"

        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to eq("Only @wit.edu email addresses are allowed.")
        expect(session[:user_id]).to be_nil
      end
    end

    context "when user has multiple connected emails" do
      let!(:admin_user) do
        user = User.create!(access_level: :admin)
        user.emails.create!(email: "admin1@wit.edu", primary: true)
        user.emails.create!(email: "admin2@wit.edu", primary: false)
        user.emails.create!(email: "admin3@wit.edu", primary: false)
        user
      end

      it "can sign in with first non-primary email" do
        OmniAuth.config.mock_auth[:google_oauth2].info.email = "admin2@wit.edu"
        get "/auth/google_oauth2/callback"

        expect(response).to redirect_to(admin_root_path)
        expect(session[:user_id]).to eq(admin_user.id)
      end

      it "can sign in with second non-primary email" do
        OmniAuth.config.mock_auth[:google_oauth2].info.email = "admin3@wit.edu"
        get "/auth/google_oauth2/callback"

        expect(response).to redirect_to(admin_root_path)
        expect(session[:user_id]).to eq(admin_user.id)
      end

      it "can sign in with primary email" do
        OmniAuth.config.mock_auth[:google_oauth2].info.email = "admin1@wit.edu"
        get "/auth/google_oauth2/callback"

        expect(response).to redirect_to(admin_root_path)
        expect(session[:user_id]).to eq(admin_user.id)
      end
    end

    context "when updating user info from OAuth" do
      let!(:admin_user) do
        user = User.create!(access_level: :admin)
        user.emails.create!(email: "admin@wit.edu", primary: true)
        user
      end

      it "sets first_name if not present" do
        expect(admin_user.first_name).to be_nil
        get "/auth/google_oauth2/callback"
        admin_user.reload
        expect(admin_user.first_name).to eq("John")
      end

      it "sets last_name if not present" do
        expect(admin_user.last_name).to be_nil
        get "/auth/google_oauth2/callback"
        admin_user.reload
        expect(admin_user.last_name).to eq("Admin")
      end

      it "does not overwrite existing names" do
        admin_user.update!(first_name: "Existing", last_name: "Name")
        get "/auth/google_oauth2/callback"
        admin_user.reload
        expect(admin_user.first_name).to eq("Existing")
        expect(admin_user.last_name).to eq("Name")
      end
    end
  end
end
