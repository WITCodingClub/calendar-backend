# frozen_string_literal: true

require "rails_helper"

RSpec.describe RefreshOauthTokensJob, type: :job do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }

  describe "#perform" do
    context "with credentials needing refresh" do
      let!(:old_credential) do
        create(:oauth_credential,
          user: user,
          refresh_token: "valid_refresh_token",
          updated_at: 8.days.ago
        )
      end

      let!(:recent_credential) do
        create(:oauth_credential,
          user: create(:user),
          refresh_token: "recent_refresh_token",
          updated_at: 2.days.ago
        )
      end

      it "only refreshes credentials older than 7 days" do
        google_credentials = instance_double(Google::Auth::UserRefreshCredentials)
        allow(Google::Auth::UserRefreshCredentials).to receive(:new).and_return(google_credentials)
        allow(google_credentials).to receive(:refresh!)
        allow(google_credentials).to receive(:access_token).and_return("new_access_token")
        allow(google_credentials).to receive(:expires_in).and_return(3600)

        expect(Google::Auth::UserRefreshCredentials).to receive(:new).once

        described_class.new.perform
      end

      it "updates the credential with new access token" do
        google_credentials = instance_double(Google::Auth::UserRefreshCredentials)
        allow(Google::Auth::UserRefreshCredentials).to receive(:new).and_return(google_credentials)
        allow(google_credentials).to receive(:refresh!)
        allow(google_credentials).to receive(:access_token).and_return("refreshed_token")
        allow(google_credentials).to receive(:expires_in).and_return(3600)

        described_class.new.perform

        old_credential.reload
        expect(old_credential.access_token).to eq("refreshed_token")
      end
    end

    context "with revoked token" do
      let!(:revoked_credential) do
        create(:oauth_credential,
          user: user,
          refresh_token: "revoked_token",
          updated_at: 8.days.ago
        )
      end

      it "marks the credential as revoked in metadata" do
        allow(Google::Auth::UserRefreshCredentials).to receive(:new).and_raise(
          Signet::AuthorizationError.new("Token has been revoked")
        )

        described_class.new.perform

        revoked_credential.reload
        expect(revoked_credential.metadata["token_revoked"]).to be true
        expect(revoked_credential.metadata["revocation_reason"]).to include("revoked")
      end
    end

    context "with no refresh token" do
      let!(:no_refresh_credential) do
        create(:oauth_credential,
          user: user,
          refresh_token: nil,
          updated_at: 8.days.ago
        )
      end

      it "skips credentials without refresh tokens" do
        expect(Google::Auth::UserRefreshCredentials).not_to receive(:new)

        described_class.new.perform
      end
    end
  end

  it "is enqueued in the low queue" do
    expect(described_class.new.queue_name).to eq("low")
  end
end
