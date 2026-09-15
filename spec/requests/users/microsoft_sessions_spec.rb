# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Signing in to the dashboard with Microsoft", type: :request do
  let(:email) { "ms.student@wit.edu" }
  let(:oid)   { "0c0ffee0-2222-4000-8000-000000000001" }
  let(:callback_path) { "/auth/microsoft/callback" }

  before do
    Flipper.enable(FlipperFlags::V1)
    OmniAuth.config.test_mode = true
  end

  after do
    OmniAuth.config.mock_auth[:microsoft] = nil
    OmniAuth.config.test_mode = false
    Flipper.disable(FlipperFlags::MICROSOFT_SIGN_IN)
    Flipper.disable(FlipperFlags::V1)
  end

  def mock_microsoft(**attributes)
    OmniAuth.config.mock_auth[:microsoft] = microsoft_auth_hash(**attributes)
  end

  context "when the flag is on and the client is configured" do
    before do
      configure_microsoft_sign_in
      Flipper.enable(FlipperFlags::MICROSOFT_SIGN_IN)
    end

    it "shows the button as a POST form next to Google" do
      get new_user_session_path

      expect(response.body).to include("Sign in with Google", "Sign in with Microsoft")
      expect(response.body).to match(%r{<form(?=[^>]*method="post")(?=[^>]*action="/auth/microsoft")[^>]*>})
    end

    it "starts the sign-in on a POST" do
      mock_microsoft(email: email, oid: oid)

      post "/auth/microsoft"

      expect(response).to be_redirect
      expect(URI(response.location).path).to eq(callback_path)
    end

    it "does not start the sign-in on a GET" do
      get "/auth/microsoft"

      expect(response).to have_http_status(:not_found)
    end

    it "creates the account and the identity for a new WIT member" do
      mock_microsoft(email: email, oid: oid)

      expect { get callback_path }.to change(User, :count).by(1)

      user = User.find_by!(email: email)
      expect(user).to be_confirmed
      expect(user.sign_in_identities.sole).to have_attributes(
        provider:  "microsoft",
        tenant_id: MicrosoftSignInHelpers::TEST_TENANT_ID,
        uid:       oid,
        email:     email
      )
      expect(response).to redirect_to(dashboard_root_path)
      expect(cookies["remember_user_token"]).to be_present
    end

    it "signs in the linked user by tenant and object id, even after the email changes" do
      identity = create(:sign_in_identity, tenant_id: MicrosoftSignInHelpers::TEST_TENANT_ID, uid: oid)
      mock_microsoft(email: "renamed.student@wit.edu", oid: oid)

      expect { get callback_path }.not_to change(User, :count)

      expect(response).to redirect_to(dashboard_root_path)
      expect(identity.reload).to have_attributes(email: "renamed.student@wit.edu", last_signed_in_at: be_present)
      get dashboard_settings_path
      expect(response.body).to include(identity.user.email)
    end

    it "links an account with the same email when a WIT member signs in" do
      user = create(:user, email: email)
      mock_microsoft(email: email, oid: oid)

      expect { get callback_path }.not_to change(User, :count)

      expect(user.sign_in_identities.sole.uid).to eq(oid)
      expect(response).to redirect_to(dashboard_root_path)
    end

    it "refuses a guest whose email matches an account, and links nothing" do
      create(:user, email: email)
      mock_microsoft(email: email, oid: oid, idp: "https://sts.windows.net/#{MicrosoftSignInHelpers::OTHER_TENANT_ID}/")

      get callback_path

      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to eq("Sign in with your WIT Microsoft account.")
      expect(SignInIdentity.count).to eq(0)
      expect(cookies["remember_user_token"]).to be_blank
    end

    it "refuses an account from another tenant" do
      mock_microsoft(email: email, oid: oid, tid: MicrosoftSignInHelpers::OTHER_TENANT_ID)

      expect { get callback_path }.not_to change(User, :count)

      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to eq("Sign in with your WIT Microsoft account.")
    end

    it "refuses an email outside the WIT domain" do
      mock_microsoft(email: "someone@example.com", oid: oid)

      expect { get callback_path }.not_to change(User, :count)

      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to eq("Only @wit.edu email addresses are allowed.")
      expect(SignInIdentity.count).to eq(0)
    end

    it "opens a Devise session and no API session" do
      mock_microsoft(email: email, oid: oid)

      expect { get callback_path }.not_to change(UserSession, :count)

      get dashboard_root_path
      expect(response).to have_http_status(:ok)
    end

    it "sends a failed sign-in back to the sign-in page" do
      OmniAuth.config.mock_auth[:microsoft] = :access_denied

      get callback_path
      expect(URI(response.location).path).to eq("/auth/failure")

      follow_redirect!
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to eq("Failed to sign in with Microsoft. Please try again.")
    end
  end

  context "when the flag is off" do
    before { configure_microsoft_sign_in }

    it "hides the button" do
      get new_user_session_path

      expect(response.body).to include("Sign in with Google")
      expect(response.body).not_to include("Sign in with Microsoft")
    end

    it "answers 404 to the start and the callback" do
      mock_microsoft(email: email, oid: oid)

      post "/auth/microsoft"
      expect(response).to have_http_status(:not_found)

      expect { get callback_path }.not_to change(User, :count)
      expect(response).to have_http_status(:not_found)
    end
  end

  context "when the client is not configured" do
    before { Flipper.enable(FlipperFlags::MICROSOFT_SIGN_IN) }

    it "hides the button and answers 404 without a client id and secret" do
      configure_microsoft_sign_in(client_id: nil, client_secret: nil)
      mock_microsoft(email: email, oid: oid)

      get new_user_session_path
      expect(response.body).not_to include("Sign in with Microsoft")

      post "/auth/microsoft"
      expect(response).to have_http_status(:not_found)

      get callback_path
      expect(response).to have_http_status(:not_found)
    end

    it "hides the button when the tenant is organizations" do
      configure_microsoft_sign_in(tenant_id: "organizations")

      get new_user_session_path

      expect(response.body).not_to include("Sign in with Microsoft")
    end
  end
end
