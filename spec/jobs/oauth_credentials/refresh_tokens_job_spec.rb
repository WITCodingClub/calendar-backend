# frozen_string_literal: true

require "rails_helper"

RSpec.describe OauthCredentials::RefreshTokensJob do
  let(:token_url) { MicrosoftGraphHelpers::TOKEN_URL }

  def stale_microsoft_credential(**attributes)
    credential = create(:oauth_credential, :microsoft, **attributes)
    credential.update_columns(updated_at: 8.days.ago) # rubocop:disable Rails/SkipsModelValidations
    credential
  end

  context "when the Entra client is configured", :microsoft_graph do
    it "refreshes a stale Microsoft credential through the Microsoft token endpoint" do
      credential = stale_microsoft_credential
      refresh = stub_request(:post, token_url)
                .with(body: hash_including("grant_type" => "refresh_token", "refresh_token" => credential.refresh_token))
                .to_return(graph_json_response("token_refresh"))

      described_class.perform_now

      expect(refresh).to have_been_requested
      expect(credential.reload.access_token).to eq(JSON.parse(graph_fixture("token_refresh"))["access_token"])
      expect(credential).not_to be_token_revoked
    end

    it "marks a Microsoft credential revoked when Microsoft answers invalid_grant" do
      credential = stale_microsoft_credential
      stub_request(:post, token_url).to_return(graph_json_response("token_invalid_grant", status: 400))

      expect { described_class.perform_now }.not_to raise_error

      expect(credential.reload).to be_token_revoked
      expect(credential.metadata).to include("revocation_reason" => "invalid_grant")
    end

    it "does not mark a credential revoked for another token error" do
      credential = stale_microsoft_credential
      stub_request(:post, token_url).to_return(status: 500, body: { error: "temporarily_unavailable" }.to_json)

      described_class.perform_now

      expect(credential.reload).not_to be_token_revoked
    end

    it "reports an unexpected refresh error and does not raise" do
      credential = stale_microsoft_credential
      stub_request(:post, token_url).to_timeout

      reports = capture_error_reports { described_class.perform_now }

      expect(reports.size).to eq(1)
      expect(reports.first).to be_handled
      expect(reports.first.context).to include(oauth_credential_id: credential.id)
      expect(credential.reload).not_to be_token_revoked
    end

    it "leaves a Microsoft credential that was updated recently" do
      create(:oauth_credential, :microsoft)

      described_class.perform_now

      expect(a_request(:post, token_url)).not_to have_been_made
    end
  end

  describe "Google credentials" do
    let(:google_token_url) { "https://oauth2.googleapis.com/token" }
    let(:credential) do
      create(:oauth_credential, refresh_token: "synthetic-refresh").tap { |c| c.update_columns(updated_at: 8.days.ago) } # rubocop:disable Rails/SkipsModelValidations
    end

    def stub_google_token_error(status, error)
      stub_request(:post, google_token_url)
        .to_return(status: status, body: { error: error }.to_json, headers: { "Content-Type" => "application/json" })
    end

    it "marks a credential revoked when Google answers invalid_grant" do
      stub_google_token_error(400, "invalid_grant")
      credential

      expect { described_class.perform_now }.not_to raise_error

      expect(credential.reload).to be_token_revoked
    end

    %w[invalid_client unauthorized_client].each do |error|
      it "leaves a credential alone and reports the error for #{error}" do
        stub_google_token_error(401, error)
        credential

        reports = capture_error_reports { described_class.perform_now }

        expect(credential.reload).not_to be_token_revoked
        expect(reports.size).to eq(1)
        expect(reports.first).to be_handled
        expect(reports.first.context).to include(oauth_credential_id: credential.id)
      end
    end
  end

  context "when the Entra client is not configured" do
    it "does not refresh Microsoft credentials" do
      stale_microsoft_credential

      described_class.perform_now

      expect(a_request(:post, token_url)).not_to have_been_made
    end
  end
end
