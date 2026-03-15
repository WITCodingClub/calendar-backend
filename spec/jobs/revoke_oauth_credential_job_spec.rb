# frozen_string_literal: true

require "rails_helper"

RSpec.describe RevokeOauthCredentialJob do
  describe "queue assignment" do
    it "is assigned to the default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end

  describe "#perform" do
    let(:user) { create(:user) }
    let(:credential) { create(:oauth_credential, user: user) }

    before do
      stub_request(:post, "https://oauth2.googleapis.com/revoke")
        .to_return(status: 200, body: "", headers: {})
    end

    context "when the credential exists" do
      it "destroys the credential" do
        credential_id = credential.id

        described_class.perform_now(credential_id)

        expect(OauthCredential.find_by(id: credential_id)).to be_nil
      end

      it "calls the Google token revocation endpoint" do
        described_class.perform_now(credential.id)

        expect(WebMock).to have_requested(:post, "https://oauth2.googleapis.com/revoke")
          .with(body: hash_including("token" => credential.access_token))
      end
    end

    context "when the credential does not exist" do
      it "returns without raising an error" do
        expect { described_class.perform_now(-1) }.not_to raise_error
      end

      it "does not attempt to revoke a token" do
        described_class.perform_now(-1)

        expect(WebMock).not_to have_requested(:post, "https://oauth2.googleapis.com/revoke")
      end
    end

    context "when Google returns HTTP 400 (token already revoked or invalid)" do
      before do
        stub_request(:post, "https://oauth2.googleapis.com/revoke")
          .to_return(status: 400, body: "", headers: {})
      end

      it "still destroys the credential" do
        credential_id = credential.id

        described_class.perform_now(credential_id)

        expect(OauthCredential.find_by(id: credential_id)).to be_nil
      end
    end

    context "when the Google revocation request raises a network error" do
      before do
        stub_request(:post, "https://oauth2.googleapis.com/revoke")
          .to_raise(StandardError.new("Network error"))
      end

      it "still destroys the credential" do
        credential_id = credential.id

        described_class.perform_now(credential_id)

        expect(OauthCredential.find_by(id: credential_id)).to be_nil
      end
    end
  end
end
