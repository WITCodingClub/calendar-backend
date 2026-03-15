# frozen_string_literal: true

# == Schema Information
#
# Table name: oauth_credentials
# Database name: primary
#
#  id               :bigint           not null, primary key
#  access_token     :string           not null
#  email            :string
#  metadata         :jsonb
#  provider         :string           not null
#  refresh_token    :string
#  token_expires_at :datetime
#  uid              :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  user_id          :bigint           not null
#
# Indexes
#
#  index_oauth_credentials_on_provider_and_uid     (provider,uid) UNIQUE
#  index_oauth_credentials_on_token_expires_at     (token_expires_at)
#  index_oauth_credentials_on_user_provider_email  (user_id,provider,email) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
require "rails_helper"

RSpec.describe OauthCredential do
  describe "associations" do
    it "belongs to user" do
      credential = create(:oauth_credential)
      expect(credential.user).to be_present
      expect(credential).to respond_to(:user)
    end
  end

  describe "validations" do
    it "requires provider" do
      credential = build(:oauth_credential, provider: nil)
      expect(credential).not_to be_valid
      expect(credential.errors[:provider]).to be_present
    end

    it "requires uid" do
      credential = build(:oauth_credential, uid: nil)
      expect(credential).not_to be_valid
      expect(credential.errors[:uid]).to be_present
    end

    it "requires access_token" do
      credential = build(:oauth_credential, access_token: nil)
      expect(credential).not_to be_valid
      expect(credential.errors[:access_token]).to be_present
    end
  end

  describe "scopes" do
    let!(:google_credential) { create(:oauth_credential) }

    it "filters by provider with for_provider scope" do
      expect(described_class.for_provider("google")).to include(google_credential)
    end

    it "filters Google credentials with google scope" do
      expect(described_class.google).to include(google_credential)
    end
  end

  describe "metadata course_calendar_id access" do
    let(:credential) { create(:oauth_credential) }

    it "stores course_calendar_id in metadata hash" do
      credential.update!(metadata: { "course_calendar_id" => "cal_123" })
      expect(credential.metadata["course_calendar_id"]).to eq("cal_123")
    end

    it "returns nil when course_calendar_id not in metadata" do
      credential.update!(metadata: {})
      expect(credential.metadata["course_calendar_id"]).to be_nil
    end
  end

  describe "#course_calendar_id" do
    it "returns the google_calendar_id from the associated GoogleCalendar" do
      credential = create(:oauth_credential)
      google_cal = create(:google_calendar, oauth_credential: credential, google_calendar_id: "cal_abc@group.calendar.google.com")

      expect(credential.course_calendar_id).to eq(google_cal.google_calendar_id)
    end

    it "returns nil when no GoogleCalendar is associated" do
      credential = create(:oauth_credential)
      expect(credential.course_calendar_id).to be_nil
    end
  end

  describe "#course_calendar_id=" do
    it "logs a deprecation warning and does not raise" do
      credential = create(:oauth_credential)
      allow(Rails.logger).to receive(:warn)

      expect { credential.course_calendar_id = "cal_xyz" }.not_to raise_error
      expect(Rails.logger).to have_received(:warn).with(/deprecated/i)
    end
  end

  describe "#token_expired?" do
    it "returns false for valid token" do
      credential = create(:oauth_credential, token_expires_at: 1.hour.from_now)
      expect(credential.token_expired?).to be false
    end

    it "returns true for expired token" do
      credential = create(:oauth_credential, :expired)
      expect(credential.token_expired?).to be true
    end

    it "returns true for token expiring within 5 minutes" do
      credential = create(:oauth_credential, token_expires_at: 4.minutes.from_now)
      expect(credential.token_expired?).to be true
    end

    it "returns true when token_expires_at is nil" do
      credential = create(:oauth_credential, token_expires_at: nil)
      expect(credential.token_expired?).to be true
    end
  end

  describe "uniqueness validation" do
    let!(:existing_credential) { create(:oauth_credential, provider: "google", uid: "123") }

    it "prevents duplicate uid for same provider" do
      duplicate = build(:oauth_credential, provider: "google", uid: "123")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:uid]).to be_present
    end
  end
end
