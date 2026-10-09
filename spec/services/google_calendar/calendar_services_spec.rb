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

      expect(service).to be_a(Google::Apis::CalendarV3::CalendarService)
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

    it "raises when the person has no Google credential" do
      expect { described_class.for_user(user) }.to raise_error(RuntimeError, "User has no Google credential")
    end
  end

  describe ".for_credential" do
    it "authorizes with that account's token while it is valid" do
      credential = create(:oauth_credential, access_token: "synthetic-second-token", token_expires_at: 1.hour.from_now)

      expect(described_class.for_credential(credential).authorization.access_token).to eq("synthetic-second-token")
    end

    it "refreshes and saves an expired token" do
      credential = create(:oauth_credential, refresh_token: "synthetic-refresh", token_expires_at: nil)
      stub_request(:post, token_url).to_return(refreshed)

      described_class.for_credential(credential)

      expect(credential.reload.access_token).to eq("synthetic-refreshed-token")
    end
  end
end
