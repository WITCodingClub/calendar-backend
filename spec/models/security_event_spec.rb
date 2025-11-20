# frozen_string_literal: true

# == Schema Information
#
# Table name: security_events
# Database name: primary
#
#  id                  :bigint           not null, primary key
#  event_type          :string           not null
#  expires_at          :datetime
#  google_subject      :string           not null
#  jti                 :string           not null
#  processed           :boolean          default(FALSE), not null
#  processed_at        :datetime
#  processing_error    :text
#  raw_event_data      :text
#  reason              :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  oauth_credential_id :bigint
#  user_id             :bigint
#
# Indexes
#
#  index_security_events_on_event_type           (event_type)
#  index_security_events_on_expires_at           (expires_at)
#  index_security_events_on_jti                  (jti) UNIQUE
#  index_security_events_on_oauth_credential_id  (oauth_credential_id)
#  index_security_events_on_processed            (processed)
#  index_security_events_on_user_id              (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (oauth_credential_id => oauth_credentials.id)
#  fk_rails_...  (user_id => users.id)
#
require "rails_helper"

RSpec.describe SecurityEvent, type: :model do
  describe "associations" do
    it { should belong_to(:user).optional }
    it { should belong_to(:oauth_credential).optional }
  end

  describe "validations" do
    it { should validate_presence_of(:jti) }
    it { should validate_presence_of(:event_type) }
    it { should validate_presence_of(:google_subject) }

    it "validates uniqueness of jti" do
      create(:security_event, jti: "unique-jti-123")
      duplicate = build(:security_event, jti: "unique-jti-123")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:jti]).to include("has already been taken")
    end
  end

  describe "scopes" do
    let!(:unprocessed_event) { create(:security_event, :tokens_revoked, processed: false) }
    let!(:processed_event) { create(:security_event, processed: true) }
    let!(:expired_event) { create(:security_event, expires_at: 1.day.ago) }
    let!(:user) { create(:user) }
    let!(:user_event) { create(:security_event, user: user) }

    describe ".unprocessed" do
      it "returns only unprocessed events" do
        expect(SecurityEvent.unprocessed).to include(unprocessed_event)
        expect(SecurityEvent.unprocessed).not_to include(processed_event)
      end
    end

    describe ".processed" do
      it "returns only processed events" do
        expect(SecurityEvent.processed).to include(processed_event)
        expect(SecurityEvent.processed).not_to include(unprocessed_event)
      end
    end

    describe ".expired" do
      it "returns only expired events" do
        expect(SecurityEvent.expired).to include(expired_event)
        expect(SecurityEvent.expired).not_to include(unprocessed_event)
      end
    end

    describe ".for_user" do
      it "returns events for specific user" do
        expect(SecurityEvent.for_user(user)).to include(user_event)
        expect(SecurityEvent.for_user(user)).not_to include(unprocessed_event)
      end
    end

    describe ".by_event_type" do
      let!(:sessions_revoked_event) do
        create(:security_event, event_type: SecurityEvent::SESSIONS_REVOKED)
      end

      it "returns events of specific type" do
        expect(SecurityEvent.by_event_type(SecurityEvent::SESSIONS_REVOKED)).to include(sessions_revoked_event)
        expect(SecurityEvent.by_event_type(SecurityEvent::SESSIONS_REVOKED)).not_to include(unprocessed_event)
      end
    end
  end

  describe "#mark_processed!" do
    let(:event) { create(:security_event, processed: false) }

    it "marks event as processed" do
      event.mark_processed!

      expect(event.reload.processed).to be true
      expect(event.processed_at).to be_present
    end

    it "can store error message" do
      event.mark_processed!(error: "Something went wrong")

      expect(event.reload.processing_error).to eq("Something went wrong")
    end
  end

  describe "#requires_immediate_action?" do
    it "returns true for sessions-revoked with hijacking reason" do
      event = build(:security_event,
                    event_type: SecurityEvent::SESSIONS_REVOKED,
                    reason: "hijacking")

      expect(event.requires_immediate_action?).to be true
    end

    it "returns true for account-disabled with hijacking reason" do
      event = build(:security_event,
                    event_type: SecurityEvent::ACCOUNT_DISABLED,
                    reason: "hijacking")

      expect(event.requires_immediate_action?).to be true
    end

    it "returns false for other event types" do
      event = build(:security_event,
                    event_type: SecurityEvent::ACCOUNT_ENABLED)

      expect(event.requires_immediate_action?).to be false
    end

    it "returns false for sessions-revoked without hijacking reason" do
      event = build(:security_event,
                    event_type: SecurityEvent::SESSIONS_REVOKED,
                    reason: "other")

      expect(event.requires_immediate_action?).to be false
    end
  end

  describe "#event_type_name" do
    it "returns the last part of the event type URI" do
      event = build(:security_event, event_type: SecurityEvent::SESSIONS_REVOKED)

      expect(event.event_type_name).to eq("sessions-revoked")
    end
  end

  describe "#verification_event?" do
    it "returns true for verification events" do
      event = build(:security_event, event_type: SecurityEvent::VERIFICATION)

      expect(event.verification_event?).to be true
    end

    it "returns false for non-verification events" do
      event = build(:security_event, event_type: SecurityEvent::SESSIONS_REVOKED)

      expect(event.verification_event?).to be false
    end
  end

  describe "before_create callback" do
    it "sets expiration date to 90 days from now" do
      event = create(:security_event)

      expect(event.expires_at).to be_within(1.second).of(90.days.from_now)
    end

    it "does not override manually set expiration" do
      custom_expiration = 30.days.from_now
      event = create(:security_event, expires_at: custom_expiration)

      expect(event.expires_at).to be_within(1.second).of(custom_expiration)
    end
  end

  describe "data encryption" do
    it "encrypts raw_event_data" do
      event = create(:security_event, raw_event_data: '{"sensitive": "data"}')

      # The raw database value should be encrypted (ciphertext)
      raw_value = SecurityEvent.connection.select_value(
        "SELECT raw_event_data FROM security_events WHERE id = #{event.id}"
      )

      expect(raw_value).not_to include("sensitive")
      expect(raw_value).not_to include("data")

      # But the model should decrypt it automatically
      expect(event.reload.raw_event_data).to eq('{"sensitive": "data"}')
    end
  end
end
