# frozen_string_literal: true

require "rails_helper"

RSpec.describe CleanupOrphanedOauthCredentialsJob do
  describe "queue assignment" do
    it "is assigned to the low queue" do
      expect(described_class.new.queue_name).to eq("low")
    end
  end

  describe "#perform" do
    let(:user) { create(:user) }
    let(:email) { create(:email, user: user, email: "test@example.com", primary: true) }
    let!(:valid_credential) do
      create(:oauth_credential,
             user: user,
             email: email.email,
             token_expires_at: 1.hour.from_now,
             refresh_token: "valid_refresh_token")
    end

    before do
      # Stub the private method that calls Google's revocation API
      allow_any_instance_of(described_class).to receive(:revoke_token_with_google)
    end

    context "when there are credentials with emails not in the system" do
      let!(:orphaned_by_email) do
        create(:oauth_credential,
               user: user,
               email: "orphaned@example.com",
               token_expires_at: 1.hour.from_now)
      end

      it "deletes credentials with non-existent emails" do
        expect {
          described_class.perform_now
        }.to change(OauthCredential, :count).by(-1)

        expect(OauthCredential.exists?(orphaned_by_email.id)).to be false
        expect(OauthCredential.exists?(valid_credential.id)).to be true
      end

      it "returns the correct counts" do
        result = described_class.perform_now

        expect(result[:deleted]).to eq(1)
        expect(result[:errors]).to eq(0)
      end
    end

    context "when there are credentials with expired tokens and no refresh token" do
      let(:expired_email) { create(:email, user: user, email: "expired@example.com", primary: false) }
      let!(:orphaned_by_expired_token) do
        create(:oauth_credential,
               user: user,
               email: expired_email.email,
               token_expires_at: 1.hour.ago,
               refresh_token: nil)
      end

      it "deletes credentials with expired tokens" do
        expect {
          described_class.perform_now
        }.to change(OauthCredential, :count).by(-1)

        expect(OauthCredential.exists?(orphaned_by_expired_token.id)).to be false
        expect(OauthCredential.exists?(valid_credential.id)).to be true
      end

      it "returns the correct counts" do
        result = described_class.perform_now

        expect(result[:deleted]).to eq(1)
        expect(result[:errors]).to eq(0)
      end
    end

    context "when there are multiple orphaned credentials" do
      let!(:orphaned_1) do
        create(:oauth_credential,
               user: user,
               email: "orphaned1@example.com",
               token_expires_at: 1.hour.from_now)
      end

      let!(:orphaned_2) do
        create(:oauth_credential,
               user: user,
               email: "orphaned2@example.com",
               token_expires_at: 1.hour.ago,
               refresh_token: nil)
      end

      it "deletes all orphaned credentials" do
        expect {
          described_class.perform_now
        }.to change(OauthCredential, :count).by(-2)

        expect(OauthCredential.exists?(orphaned_1.id)).to be false
        expect(OauthCredential.exists?(orphaned_2.id)).to be false
        expect(OauthCredential.exists?(valid_credential.id)).to be true
      end

      it "returns the correct counts" do
        result = described_class.perform_now

        expect(result[:deleted]).to eq(2)
        expect(result[:errors]).to eq(0)
      end
    end

    context "when there are no orphaned credentials" do
      it "does not delete any credentials" do
        expect {
          described_class.perform_now
        }.not_to change(OauthCredential, :count)
      end

      it "returns zero counts" do
        result = described_class.perform_now

        expect(result[:deleted]).to eq(0)
        expect(result[:errors]).to eq(0)
      end
    end

    context "when deletion fails" do
      let!(:orphaned_credential) do
        create(:oauth_credential,
               user: user,
               email: "orphaned@example.com",
               token_expires_at: 1.hour.from_now)
      end

      before do
        allow_any_instance_of(OauthCredential).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed.new("Deletion failed"))
      end

      it "logs the error and continues" do
        result = described_class.perform_now

        expect(result[:errors]).to eq(1)
        expect(result[:deleted]).to eq(0)
      end

      it "does not raise an exception" do
        expect {
          described_class.perform_now
        }.not_to raise_error
      end
    end
  end

  describe "#determine_orphan_reason" do
    let(:user) { create(:user) }
    let(:job) { described_class.new }

    context "when email is not in the system" do
      let(:credential) do
        create(:oauth_credential, user: user, email: "nonexistent@example.com")
      end

      it "returns email not found reason" do
        reason = job.send(:determine_orphan_reason, credential)
        expect(reason).to eq("Email not found in system")
      end
    end

    context "when token is expired without refresh capability" do
      let(:email) { create(:email, user: user, email: "test@example.com") }
      let(:credential) do
        create(:oauth_credential,
               user: user,
               email: email.email,
               token_expires_at: 1.hour.ago,
               refresh_token: nil)
      end

      it "returns expired token reason" do
        reason = job.send(:determine_orphan_reason, credential)
        expect(reason).to eq("Expired token without refresh capability")
      end
    end
  end
end
