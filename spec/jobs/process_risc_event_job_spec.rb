# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProcessRiscEventJob, type: :job do
  CONFIGURATION_URL = RiscValidationService::RISC_CONFIGURATION_URL
  JWKS_URL = "https://www.googleapis.com/service_accounts/v1/risc/v1/jwks"
  ISSUER = "https://accounts.google.com"
  AUDIENCE = "factory-test-client-id"

  let(:rsa_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:kid) { "test-key-1" }

  def stub_google_risc_endpoints
    stub_request(:get, CONFIGURATION_URL)
      .to_return(status: 200, body: { issuer: ISSUER, jwks_uri: JWKS_URL }.to_json)

    jwk = JSON.parse(JWT::JWK.new(rsa_key, kid: kid).export.to_json)
    stub_request(:get, JWKS_URL).to_return(status: 200, body: { keys: [ jwk ] }.to_json)
  end

  def build_token(event_type:, subject: nil, jti: "factory-jti-1", reason: nil, state: nil)
    event_details = {}
    event_details["subject"] = { "subject_type" => "iss-sub", "sub" => subject } if subject
    event_details["reason"] = reason if reason
    event_details["state"] = state if state

    payload = {
      "iss" => ISSUER,
      "aud" => AUDIENCE,
      "iat" => Time.now.to_i,
      "jti" => jti,
      "events" => { event_type => event_details }
    }

    JWT.encode(payload, rsa_key, "RS256", { kid: kid })
  end

  around do |example|
    previous = ENV.fetch("GOOGLE_OAUTH_CLIENT_IDS", nil)
    ENV["GOOGLE_OAUTH_CLIENT_IDS"] = AUDIENCE
    example.run
    if previous.nil?
      ENV.delete("GOOGLE_OAUTH_CLIENT_IDS")
    else
      ENV["GOOGLE_OAUTH_CLIENT_IDS"] = previous
    end
  end

  it "logs and marks a verification event processed when it carries a subject" do
    stub_google_risc_endpoints
    token = build_token(
      event_type: "https://schemas.openid.net/secevent/risc/event-type/verification",
      subject: "some-google-subject", jti: "verify-jti", state: "opaque-state"
    )

    described_class.perform_now(token)

    event = SecurityEvent.find_by(jti: "verify-jti")
    expect(event).to be_present
    expect(event.processed).to be(true)
    expect(event.verification_event?).to be(true)
  end

  # Bug: SecurityEvent requires google_subject to be present, but a real RISC
  # verification ping (a health check with no affected account) has no
  # "subject" object at all. RiscEventHandlerService#create_security_event
  # always passes event_data[:google_subject] through, so SecurityEvent.create!
  # raises ActiveRecord::RecordInvalid; RiscEventHandlerService#process rescues
  # it and returns success: false, and ProcessRiscEventJob never inspects that
  # return value, so the job "succeeds" without ever recording the event or
  # raising. Not fixed here because it changes model validation or event
  # handling; documented as current behavior.
  it "silently drops a verification event that has no subject, as real RISC pings do" do
    stub_google_risc_endpoints
    token = build_token(
      event_type: "https://schemas.openid.net/secevent/risc/event-type/verification",
      jti: "verify-no-subject-jti", state: "opaque-state"
    )

    expect { described_class.perform_now(token) }.not_to raise_error
    expect(SecurityEvent.find_by(jti: "verify-no-subject-jti")).to be_nil
  end

  it "revokes a user's google oauth credentials for a sessions-revoked event" do
    stub_google_risc_endpoints
    user = create(:user)
    credential = create(:oauth_credential, user: user, uid: "google-subject-123")
    token = build_token(
      event_type: SecurityEvent::SESSIONS_REVOKED,
      subject: "google-subject-123", jti: "sessions-revoked-jti"
    )

    described_class.perform_now(token)

    expect(OauthCredential.exists?(credential.id)).to be(false)
    event = SecurityEvent.find_by(jti: "sessions-revoked-jti")
    expect(event.processed).to be(true)
    expect(event.user).to eq(user)
  end

  it "records the event as unmatched when no user has that google subject" do
    stub_google_risc_endpoints
    token = build_token(
      event_type: SecurityEvent::ACCOUNT_DISABLED,
      subject: "someone-we-have-never-seen", jti: "unknown-user-jti"
    )

    expect { described_class.perform_now(token) }.not_to raise_error

    event = SecurityEvent.find_by(jti: "unknown-user-jti")
    expect(event.processed).to be(true)
    expect(event.processing_error).to eq("User not found")
  end

  it "skips reprocessing an event whose jti was already recorded" do
    stub_google_risc_endpoints
    create(:security_event, jti: "already-seen-jti")
    token = build_token(event_type: SecurityEvent::TOKEN_REVOKED, subject: "some-subject", jti: "already-seen-jti")

    expect(RiscEventHandlerService).not_to receive(:new)

    described_class.perform_now(token)
  end

  it "discards the job without raising when the token fails validation" do
    stub_google_risc_endpoints

    expect { described_class.perform_now("not-a-real-jwt") }.not_to raise_error
    expect(SecurityEvent.count).to eq(0)
  end

  it "retries instead of raising when an unexpected error occurs while handling the event" do
    stub_google_risc_endpoints
    token = build_token(event_type: SecurityEvent::ACCOUNT_ENABLED, subject: "some-subject", jti: "retry-me-jti")
    allow(RiscEventHandlerService).to receive(:new).and_raise(StandardError, "boom")

    expect { described_class.perform_now(token) }.to have_enqueued_job(described_class).with(token)
  end
end
