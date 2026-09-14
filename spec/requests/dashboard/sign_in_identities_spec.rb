# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::SignInIdentities", type: :request do
  let(:current_user) { create(:user) }
  let!(:identity)    { create(:sign_in_identity, user: current_user) }

  before { sign_in current_user }

  it "lists the Microsoft sign-in on the settings page" do
    get dashboard_settings_path

    expect(response.body).to include("Microsoft sign-in", identity.email)
  end

  describe "DELETE /dashboard/sign_in_identities/:id" do
    it "removes the identity" do
      expect { delete dashboard_sign_in_identity_path(identity) }.to change(SignInIdentity, :count).by(-1)

      expect(response).to redirect_to(dashboard_settings_path)
      expect(flash[:notice]).to eq("Microsoft sign-in removed.")
    end

    it "keeps the sessions that Google and a passkey opened, and the current session" do
      google_session  = create(:user_session, user: current_user, source: "google_onboard")
      passkey_session = create(:user_session, user: current_user, source: "passkey",
                                              passkey: create(:passkey, user: current_user))

      delete dashboard_sign_in_identity_path(identity)

      expect(google_session.reload).to be_active
      expect(passkey_session.reload).to be_active
      get dashboard_settings_path
      expect(response).to have_http_status(:ok)
    end

    it "does not remove another person's identity" do
      other = create(:sign_in_identity)

      expect { delete dashboard_sign_in_identity_path(other) }.not_to change(SignInIdentity, :count)

      expect(flash[:alert]).to eq("Sign-in account not found.")
    end
  end
end
