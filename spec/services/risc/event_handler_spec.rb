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
      allow(GoogleCalendar::CalendarManager).to receive(:new).and_raise(StandardError, "synthetic failure")
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

  describe "the action of each event type" do
    def process(event_type, reason: nil)
      described_class.new(event_data.merge(jti: "synthetic-#{SecureRandom.hex(4)}", event_type:, reason:)).process
    end

    {
      SecurityEvent::SESSIONS_REVOKED => "sessions_revoked",
      SecurityEvent::TOKENS_REVOKED   => "tokens_revoked"
    }.each do |event_type, action|
      it "revokes every Google credential for #{action}" do
        expect(process(event_type)).to eq(success: true, action: action, oauth_credentials_revoked: true)
        expect(OauthCredential.exists?(credential.id)).to be(false)
      end
    end

    {
      SecurityEvent::ACCOUNT_ENABLED                    => "account_enabled",
      SecurityEvent::ACCOUNT_CREDENTIAL_CHANGE_REQUIRED => "credential_change_required"
    }.each do |event_type, action|
      it "only records #{action}" do
        expect(process(event_type)).to eq(success: true, action: action)
        expect(OauthCredential.exists?(credential.id)).to be(true)
      end
    end

    it "revokes the credentials of a hijacked account only" do
      expect(process(SecurityEvent::ACCOUNT_DISABLED, reason: "bulk-account")).to eq(success: true, action: "account_disabled", reason: "bulk-account")
      expect(OauthCredential.exists?(credential.id)).to be(true)

      expect(process(SecurityEvent::ACCOUNT_DISABLED, reason: "hijacking"))
        .to eq(success: true, action: "account_disabled_hijacking", oauth_credentials_revoked: true)
      expect(OauthCredential.exists?(credential.id)).to be(false)
    end

    it "marks an unknown event type processed" do
      expect(process("https://schemas.example.test/unknown")).to eq(success: true, action: "unknown_event_type")
    end
  end

  describe "a token-revoked event" do
    let(:revoked_token) { "1//synthetic-refresh-token-revoked" }
    let(:kept_token) { "1//synthetic-refresh-token-kept" }
    let!(:named) { create(:oauth_credential, user: user, email: "named@example.test", refresh_token: revoked_token) }
    let!(:other) { create(:oauth_credential, user: user, email: "other@example.test", refresh_token: kept_token) }

    def double_sha512(token)
      Base64.strict_encode64(Digest::SHA512.digest(Digest::SHA512.digest(token)))
    end

    def token_revoked(token:, algorithm: "hash_base64_sha512_sha512", token_type: "refresh_token", subject: nil)
      described_class.new(
        jti:              "synthetic-token-revoked-#{SecureRandom.hex(4)}",
        event_type:       SecurityEvent::TOKEN_REVOKED,
        google_subject:   subject,
        token_identifier: { token_type:, algorithm:, token: },
        reason:           nil,
        raw_event_data:   "{}"
      ).process
    end

    it "revokes only the credential whose refresh token the event names" do
      result = token_revoked(token: double_sha512(revoked_token), subject: named.uid)

      expect(result).to eq(success: true, action: "token_revoked", oauth_credentials_revoked: true, oauth_credential_ids: [ named.id ])
      expect(named.reload).to have_attributes(refresh_token: nil, token_revoked?: true)
      expect(other.reload).to have_attributes(refresh_token: kept_token, token_revoked?: false)
      expect(credential.reload).not_to be_token_revoked
      expect(SecurityEvent.last).to have_attributes(processed: true, user: user, oauth_credential: named, google_subject: named.uid)
    end

    it "finds the credential without a subject, and records its Google account" do
      result = token_revoked(token: double_sha512(revoked_token))

      expect(result).to include(action: "token_revoked", oauth_credential_ids: [ named.id ])
      expect(named.reload.refresh_token).to be_nil
      expect(other.reload.refresh_token).to eq(kept_token)
      expect(SecurityEvent.last).to have_attributes(processed: true, user: user, google_subject: named.uid)
    end

    it "revokes the one credential that a 16-character prefix matches" do
      unique = create(:oauth_credential, user: user, email: "unique@example.test", refresh_token: "1//unique-prefix-0123456789")

      expect(token_revoked(token: "1//unique-prefix", algorithm: "prefix")).to include(action: "token_revoked", oauth_credential_ids: [ unique.id ])
      expect(unique.reload.refresh_token).to be_nil
    end

    it "revokes nothing and reports when a prefix matches more than one credential" do
      allow(Rails.error).to receive(:report)

      # Both synthetic tokens share their first 16 characters.
      result = token_revoked(token: revoked_token.first(16), algorithm: "prefix")

      expect(result).to eq(success: true, action: "token_ambiguous", oauth_credential_ids: [ named.id, other.id ].sort)
      expect(named.reload.refresh_token).to eq(revoked_token)
      expect(other.reload.refresh_token).to eq(kept_token)
      expect(SecurityEvent.last).to have_attributes(processed: true, oauth_credential: nil)
      expect(Rails.error).to have_received(:report)
        .with(an_instance_of(described_class::TokenAmbiguous), handled: true, context: hash_including(oauth_credential_ids: [ named.id, other.id ].sort))
    end

    it "skips and reports a candidate whose refresh token does not decrypt" do
      broken = create(:oauth_credential, user: user, email: "broken@example.test")
      # A value encrypted with a key the app no longer has. Raw SQL, because
      # update_column would encrypt it.
      broken_value = { p: "c3ludGhldGlj", h: { iv: "c3ludGhldGlj", at: "c3ludGhldGlj" } }.to_json
      OauthCredential.connection.exec_update(
        "UPDATE oauth_credentials SET refresh_token = $1 WHERE id = $2", "SQL", [ broken_value, broken.id ]
      )
      allow(Rails.error).to receive(:report)

      result = token_revoked(token: double_sha512(revoked_token))

      expect(result).to include(action: "token_revoked", oauth_credential_ids: [ named.id ])
      expect(Rails.error).to have_received(:report)
        .with(a_kind_of(ActiveRecord::Encryption::Errors::Base), handled: true, context: { oauth_credential_id: broken.id })
    end

    it "revokes a credential that no longer passes its validations" do
      named.update_column(:email, "not-an-email")

      expect(token_revoked(token: double_sha512(revoked_token))).to include(action: "token_revoked")
      expect(named.reload).to have_attributes(refresh_token: nil, token_revoked?: true)
    end

    it "leaves an unprocessed event row when the match fails for a moment" do
      allow_any_instance_of(Risc::TokenMatcher).to receive(:matching_ids).and_raise(ActiveRecord::StatementTimeout) # rubocop:disable RSpec/AnyInstance

      expect { token_revoked(token: double_sha512(revoked_token)) }.to raise_error(ActiveRecord::StatementTimeout)
      expect(SecurityEvent.last).to have_attributes(event_type: SecurityEvent::TOKEN_REVOKED, processed: false)
      expect(named.reload.refresh_token).to eq(revoked_token)
    end

    it "does not look past the credential of the subject" do
      result = token_revoked(token: double_sha512(revoked_token), subject: other.uid)

      expect(result).to eq(success: true, action: "token_not_found")
      expect(named.reload.refresh_token).to eq(revoked_token)
    end

    it "records an unknown token as handled and changes nothing" do
      result = token_revoked(token: double_sha512("1//synthetic-refresh-token-unknown"))

      expect(result).to eq(success: true, action: "token_not_found")
      expect(named.reload).to have_attributes(refresh_token: revoked_token, token_revoked?: false)
      expect(other.reload.refresh_token).to eq(kept_token)
      expect(SecurityEvent.last).to have_attributes(processed: true, processing_error: nil, user: nil,
                                                    google_subject: described_class::UNKNOWN_SUBJECT)
    end

    it "ignores a token type or identifier that Google does not document" do
      expect(token_revoked(token: double_sha512(revoked_token), token_type: "access_token"))
        .to eq(success: true, action: "token_identifier_unsupported")
      expect(token_revoked(token: revoked_token, algorithm: "plain"))
        .to eq(success: true, action: "token_identifier_unsupported")
      expect(named.reload.refresh_token).to eq(revoked_token)
    end
  end
end
