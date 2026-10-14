# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleOauthable do
  let(:user) { create(:user) }

  describe "#reset_google_credential" do
    it "reads the credential again on the next call" do
      expect(user.google_credential).to be_nil

      credential = create(:oauth_credential, user: user)
      user.reset_google_credential

      expect(user.google_credential).to eq(credential)
    end

    it "does nothing when no credential is cached" do
      expect { user.reset_google_credential }.not_to raise_error
    end
  end

  describe "#refresh_google_token!" do
    it "keeps the credential readable after the refresh" do
      credential = create(:oauth_credential, user: user, refresh_token: "synthetic-refresh", token_expires_at: 1.minute.ago)
      stub_request(:post, "https://oauth2.googleapis.com/token").to_return(
        status: 200, body: { access_token: "synthetic-refreshed-token", expires_in: 3600, token_type: "Bearer" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      user.refresh_google_token!

      expect(user.google_credential).to eq(credential)
      expect(user.google_access_token).to eq("synthetic-refreshed-token")
    end
  end
end
