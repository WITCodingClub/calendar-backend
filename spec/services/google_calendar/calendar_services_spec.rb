# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendar::CalendarServices do
  let(:token_url) { "https://oauth2.googleapis.com/token" }
  let(:refreshed) do
    { status: 200, body: { access_token: "synthetic-refreshed-token", expires_in: 3600, token_type: "Bearer" }.to_json,
      headers: { "Content-Type" => "application/json" } }
  end

  describe ".service_account" do
    before { stub_google_service_account }

    it "authorizes with the service account" do
      service = described_class.service_account

      expect(service.authorization.access_token).to eq("synthetic-service-account-token")
    end
  end

  describe ".for_user" do
    let(:user) { create(:user) }

    it "authorizes with the person's token while it is valid" do
      create(:oauth_credential, user: user, access_token: "synthetic-user-token", token_expires_at: 1.hour.from_now)

      expect(described_class.for_user(user).authorization.access_token).to eq("synthetic-user-token")
    end

    it "refreshes and saves an expired token" do
      credential = create(:oauth_credential, user: user, refresh_token: "synthetic-refresh", token_expires_at: 1.minute.ago)
      refresh    = stub_request(:post, token_url).to_return(refreshed)

      service = described_class.for_user(user)

      expect(refresh).to have_been_requested.once
      expect(service.authorization.access_token).to eq("synthetic-refreshed-token")
      expect(credential.reload.access_token).to eq("synthetic-refreshed-token")
    end

    # A sync builds the service more than once on the same user. After a
    # refresh, the next build must still find the credential.
    it "builds the service again after it refreshed a token" do
      create(:oauth_credential, user: user, refresh_token: "synthetic-refresh", token_expires_at: 1.minute.ago)
      stub_request(:post, token_url).to_return(refreshed)

      described_class.for_user(user)

      expect(described_class.for_user(user).authorization.access_token).to eq("synthetic-refreshed-token")
    end

    it "raises when the person has no Google credential" do
      expect { described_class.for_user(user) }.to raise_error(RuntimeError, "User has no Google credential")
    end
  end

  describe ".for_credential" do
    it "authorizes with that account's token while it is valid" do
      credential = create(:oauth_credential, access_token: "synthetic-second-token", token_expires_at: 1.hour.from_now)

      expect(described_class.for_credential(credential).authorization.access_token).to eq("synthetic-second-token")
    end

    it "refreshes and saves a token with no expiry time" do
      credential = create(:oauth_credential, refresh_token: "synthetic-refresh", token_expires_at: nil)
      stub_request(:post, token_url).to_return(refreshed)

      described_class.for_credential(credential)

      expect(credential.reload.access_token).to eq("synthetic-refreshed-token")
    end
  end

  describe ".authorization" do
    let(:google_token_url) { "https://oauth2.googleapis.com/token" }

    def stub_google_token(status, body)
      stub_request(:post, google_token_url)
        .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
    end

    it "uses a token that has not expired without a refresh" do
      credential = create(:oauth_credential, token_expires_at: 1.hour.from_now)

      expect(described_class.authorization(credential).access_token).to eq(credential.access_token)
      expect(a_request(:post, google_token_url)).not_to have_been_made
    end

    it "refreshes and saves an expired token" do
      credential = create(:oauth_credential, refresh_token: "synthetic-refresh", token_expires_at: 1.minute.ago)
      stub_google_token(200, { access_token: "synthetic-refreshed-token", expires_in: 3600, token_type: "Bearer" })

      described_class.authorization(credential)

      expect(credential.reload.access_token).to eq("synthetic-refreshed-token")
      expect(credential.token_expires_at).to be > 50.minutes.from_now
    end

    it "marks the credential revoked when Google answers invalid_grant" do
      credential = create(:oauth_credential, refresh_token: "synthetic-refresh", token_expires_at: 1.minute.ago)
      stub_google_token(400, { error: "invalid_grant" })

      expect { described_class.authorization(credential) }.to raise_error(Signet::AuthorizationError)
      expect(credential.reload).to be_token_revoked
    end

    it "does not mark the credential revoked for another token error" do
      credential = create(:oauth_credential, refresh_token: "synthetic-refresh", token_expires_at: 1.minute.ago)
      stub_google_token(401, { error: "invalid_client" })

      expect { described_class.authorization(credential) }.to raise_error(Signet::AuthorizationError)
      expect(credential.reload).not_to be_token_revoked
    end
  end
end
