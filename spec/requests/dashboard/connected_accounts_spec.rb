# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::ConnectedAccounts", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  def disconnect_path_for(credential)
    get dashboard_connected_accounts_path
    form = Nokogiri::HTML(response.body).at_css("form[action*='/dashboard/connected_accounts/'][action*='#{credential.public_id}']")
    form["action"]
  end

  describe "DELETE /dashboard/connected_accounts/:id" do
    it "disconnects a Google credential and redirects with the success notice" do
      credential = create(:oauth_credential, user: user)
      create(:oauth_credential, user: user, email: Faker::Internet.email)

      delete disconnect_path_for(credential)

      expect(response).to redirect_to(dashboard_connected_accounts_path)
      follow_redirect!
      expect(response.body).to include("Account disconnected.")
      expect(OauthCredential.exists?(credential.id)).to be(false)
    end

    it "does not remove a credential that belongs to another user" do
      create(:oauth_credential, user: user)
      other_credential = create(:oauth_credential, user: create(:user))

      delete dashboard_connected_account_path(other_credential.public_id)

      expect(response).to redirect_to(dashboard_connected_accounts_path)
      follow_redirect!
      expect(response.body).to include("Credential not found.")
      expect(OauthCredential.exists?(other_credential.id)).to be(true)
    end
  end
end
