# frozen_string_literal: true

require "rails_helper"

RSpec.describe CleanupOrphanedOauthCredentialsJob do
  let(:google_revoke_url) { "https://oauth2.googleapis.com/revoke" }

  it "sends an orphaned Google token to Google's revoke endpoint" do
    revoke = stub_request(:post, google_revoke_url).to_return(status: 200)
    create(:oauth_credential, token_expires_at: 1.day.ago, refresh_token: nil)

    described_class.perform_now

    expect(revoke).to have_been_requested
  end

  it "does not send a Microsoft token to Google" do
    create(:oauth_credential, :microsoft, token_expires_at: 1.day.ago, refresh_token: nil)

    described_class.perform_now

    expect(a_request(:post, google_revoke_url)).not_to have_been_made
  end
end
