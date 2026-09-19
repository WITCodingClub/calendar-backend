# frozen_string_literal: true

require "rails_helper"

RSpec.describe RiscEventHandlerService do
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
      allow(GoogleCalendarService).to receive(:new).and_raise(StandardError, "synthetic failure")
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
end
