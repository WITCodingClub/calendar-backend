# == Schema Information
#
# Table name: oauth_credentials
# Database name: primary
#
#  id               :bigint           not null, primary key
#  access_token     :string           not null
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
#  index_oauth_credentials_on_provider_and_uid      (provider,uid) UNIQUE
#  index_oauth_credentials_on_user_id               (user_id)
#  index_oauth_credentials_on_user_id_and_provider  (user_id,provider) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
require 'rails_helper'

RSpec.describe OauthCredential, type: :model do
  describe "associations" do
    it { should belong_to(:user) }
  end

  describe "validations" do
    it { should validate_presence_of(:provider) }
    it { should validate_presence_of(:uid) }
    it { should validate_presence_of(:access_token) }
  end

  describe "scopes" do
    let!(:google_credential) { create(:oauth_credential) }

    it "filters by provider with for_provider scope" do
      expect(OauthCredential.for_provider("google")).to include(google_credential)
    end

    it "filters Google credentials with google scope" do
      expect(OauthCredential.google).to include(google_credential)
    end
  end

  describe "#course_calendar_id" do
    let(:credential) { create(:oauth_credential) }

    it "returns nil when metadata is empty" do
      expect(credential.course_calendar_id).to be_nil
    end

    it "returns course_calendar_id from metadata when present" do
      credential.update!(metadata: { "course_calendar_id" => "cal_123" })
      expect(credential.course_calendar_id).to eq("cal_123")
    end
  end

  describe "#course_calendar_id=" do
    let(:credential) { create(:oauth_credential) }

    it "sets course_calendar_id in metadata" do
      credential.course_calendar_id = "cal_456"
      expect(credential.metadata["course_calendar_id"]).to eq("cal_456")
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
