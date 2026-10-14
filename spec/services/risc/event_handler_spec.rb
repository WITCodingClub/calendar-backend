# frozen_string_literal: true

require "rails_helper"

RSpec.describe Risc::EventHandler do
  let(:user) { create(:user) }
  let!(:credential) { create(:oauth_credential, user: user, uid: "synthetic-google-subject") }
  let(:event_data) do
    {
      jti:            "synthetic-sessions-revoked-jti",
      event_type:     SecurityEvent::SESSIONS_REVOKED,
      google_subject: "synthetic-google-subject",
      reason:         nil,
      raw_event_data: "{}"
    }
  end

  describe "when a credential cannot be revoked" do
    before do
      create(:course_calendar, oauth_credential: credential)
      # Stands in for a bug in the disconnect path, which OauthCredential does
      # not rescue.
      allow(GoogleCalendar::Provider).to receive(:new).and_raise(StandardError, "synthetic failure")
    end

    it "raises so that the job retries, and does not report the credential as revoked" do
      expect { described_class.new(event_data).process }.to raise_error(/synthetic failure/)

      expect(OauthCredential.exists?(credential.id)).to be(true)
      expect(SecurityEvent.find_by(jti: "synthetic-sessions-revoked-jti").processed).to be(false)
    end
  end

  it "processes an event again when an earlier attempt left it unprocessed" do
    create(:security_event, jti: "synthetic-sessions-revoked-jti", processed: false)

    result = described_class.new(event_data).process

    expect(result).to include(success: true, oauth_credentials_revoked: true)
    expect(OauthCredential.exists?(credential.id)).to be(false)
    expect(SecurityEvent.find_by(jti: "synthetic-sessions-revoked-jti").processed).to be(true)
  end

  describe "when the database fails for a moment" do
    [
      ActiveRecord::ConnectionNotEstablished,
      ActiveRecord::StatementTimeout,
      ActiveRecord::LockWaitTimeout,
      ActiveRecord::Deadlocked
    ].each do |error_class|
      it "raises #{error_class} from the event row so that the job retries" do
        allow(SecurityEvent).to receive(:find_or_initialize_by).and_raise(error_class, "synthetic failure")
        allow(Rails.error).to receive(:report)

        expect { described_class.new(event_data).process }.to raise_error(error_class)

        expect(Rails.error).not_to have_received(:report)
      end
    end

    it "raises when the event cannot be marked processed, and does not record that as a handler error" do
      allow_any_instance_of(SecurityEvent).to receive(:mark_processed!).and_raise(ActiveRecord::StatementTimeout) # rubocop:disable RSpec/AnyInstance

      expect { described_class.new(event_data).process }.to raise_error(ActiveRecord::StatementTimeout)
    end
  end

  it "records a handler failure that a retry cannot fix, reports it, and returns success false" do
    # A verification ping has no subject, and the event row requires one.
    data = event_data.merge(event_type: SecurityEvent::VERIFICATION, google_subject: nil)
    allow(Rails.error).to receive(:report)

    result = described_class.new(data).process

    expect(result).to include(success: false)
    expect(Rails.error).to have_received(:report).with(an_instance_of(ActiveRecord::RecordInvalid), handled: true, context: { jti: data[:jti] })
  end
end
