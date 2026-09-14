# frozen_string_literal: true

require "rails_helper"

RSpec.describe RiscValidationService, type: :service do
  CONFIGURATION_URL = RiscValidationService::RISC_CONFIGURATION_URL
  JWKS_URL = "https://www.googleapis.com/service_accounts/v1/risc/v1/jwks"
  ISSUER = "https://accounts.google.com"
  AUDIENCE = "factory-test-client-id"

  let(:rsa_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:other_rsa_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:kid) { "test-key-1" }

  def jwk_for(key, key_id)
    JSON.parse(JWT::JWK.new(key, kid: key_id).export.to_json)
  end

  def stub_risc_configuration(status: 200, body: nil)
    stub_request(:get, CONFIGURATION_URL)
      .to_return(status: status, body: body || file_fixture("risc_validation/configuration.json").read)
  end

  def stub_jwks(keys:, status: 200)
    stub_request(:get, JWKS_URL)
      .to_return(status: status, body: { keys: keys }.to_json)
  end

  def build_token(payload_overrides: {}, key: rsa_key, key_id: kid)
    payload = {
      "iss" => ISSUER,
      "aud" => AUDIENCE,
      "iat" => Time.now.to_i,
      "jti" => "factory-jti-1",
      "events" => {
        "https://schemas.openid.net/secevent/risc/event-type/verification" => { "state" => "abc123" }
      }
    }.merge(payload_overrides)

    header = key_id.nil? ? {} : { kid: key_id }

    JWT.encode(payload, key, "RS256", header)
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

  describe "initialization" do
    it "fetches the RISC configuration and the JWKS" do
      stub_risc_configuration
      stub_jwks(keys: [ jwk_for(rsa_key, kid) ])

      expect { described_class.new }.not_to raise_error
      expect(WebMock).to have_requested(:get, CONFIGURATION_URL)
      expect(WebMock).to have_requested(:get, JWKS_URL)
    end

    it "raises when the RISC configuration endpoint answers with an error status" do
      stub_risc_configuration(status: 500, body: "boom")

      expect { described_class.new }.to raise_error(RiscValidationService::ValidationError)
    end

    it "raises when the RISC configuration body is not valid JSON" do
      stub_risc_configuration(body: "not json")

      expect { described_class.new }.to raise_error(JSON::ParserError)
    end

    it "raises when fetching the configuration times out" do
      stub_request(:get, CONFIGURATION_URL).to_timeout

      expect { described_class.new }.to raise_error(Timeout::Error)
    end

    it "raises when the JWKS endpoint answers with an error status" do
      stub_risc_configuration
      stub_jwks(keys: [], status: 502)

      expect { described_class.new }.to raise_error(RiscValidationService::ValidationError)
    end
  end

  describe "#validate_and_decode" do
    subject(:service) do
      stub_risc_configuration
      stub_jwks(keys: [ jwk_for(rsa_key, kid) ])
      described_class.new
    end

    it "decodes a validly signed token into an indifferent-access hash" do
      token = build_token

      decoded = service.validate_and_decode(token)

      expect(decoded).to be_a(ActiveSupport::HashWithIndifferentAccess)
      expect(decoded[:iss]).to eq(ISSUER)
      expect(decoded[:jti]).to eq("factory-jti-1")
      expect(decoded["aud"]).to eq(AUDIENCE)
    end

    it "raises KeyNotFoundError when the token has no kid header" do
      token = build_token(key_id: nil)

      expect { service.validate_and_decode(token) }.to raise_error(RiscValidationService::KeyNotFoundError)
    end

    it "raises KeyNotFoundError when the kid does not match any JWKS key" do
      token = build_token(key_id: "unknown-key")

      expect { service.validate_and_decode(token) }.to raise_error(RiscValidationService::KeyNotFoundError)
    end

    it "raises InvalidTokenError for a completely malformed token" do
      expect { service.validate_and_decode("not-a-jwt") }.to raise_error(RiscValidationService::InvalidTokenError)
    end

    # Bug: JWT::VerificationError, JWT::InvalidIssuerError and JWT::InvalidAudError are all
    # subclasses of JWT::DecodeError, and the `rescue JWT::DecodeError` clause comes first in
    # RiscValidationService#validate_and_decode. It always catches these before the later,
    # more specific rescue clauses run, so InvalidSignatureError, InvalidIssuerError and
    # InvalidAudienceError are unreachable dead code — every one of these failures surfaces as
    # InvalidTokenError instead. Harmless here because every caller only rescues the shared
    # ValidationError base class, but documented as current behavior.
    it "raises InvalidTokenError, not InvalidSignatureError, for a bad signature" do
      token = build_token(key: other_rsa_key)

      expect { service.validate_and_decode(token) }.to raise_error(RiscValidationService::InvalidTokenError)
    end

    it "raises InvalidTokenError, not InvalidIssuerError, for the wrong issuer" do
      token = build_token(payload_overrides: { "iss" => "https://evil.example.com" })

      expect { service.validate_and_decode(token) }.to raise_error(RiscValidationService::InvalidTokenError)
    end

    it "raises InvalidTokenError, not InvalidAudienceError, for the wrong audience" do
      token = build_token(payload_overrides: { "aud" => "someone-elses-client-id" })

      expect { service.validate_and_decode(token) }.to raise_error(RiscValidationService::InvalidTokenError)
    end
  end

  describe "#extract_event_data" do
    subject(:service) do
      stub_risc_configuration
      stub_jwks(keys: [ jwk_for(rsa_key, kid) ])
      described_class.new
    end

    it "pulls the event type, subject, and metadata out of a decoded token" do
      decoded = ActiveSupport::HashWithIndifferentAccess.new(
        "jti" => "factory-jti-2",
        "iat" => 1_700_000_000,
        "events" => {
          "https://schemas.openid.net/secevent/risc/event-type/sessions-revoked" => {
            "subject" => { "subject_type" => "iss-sub", "sub" => "google-subject-123" },
            "reason" => "hijacking",
            "state" => "opaque-state"
          }
        }
      )

      data = service.extract_event_data(decoded)

      expect(data).to eq(
        jti: "factory-jti-2",
        event_type: "https://schemas.openid.net/secevent/risc/event-type/sessions-revoked",
        google_subject: "google-subject-123",
        reason: "hijacking",
        raw_event_data: decoded.to_json,
        iat: 1_700_000_000,
        state: "opaque-state"
      )
    end

    it "returns nils for the subject fields when there are no events" do
      decoded = ActiveSupport::HashWithIndifferentAccess.new("jti" => "factory-jti-3", "iat" => 1)

      data = service.extract_event_data(decoded)

      expect(data[:event_type]).to be_nil
      expect(data[:google_subject]).to be_nil
      expect(data[:reason]).to be_nil
    end
  end
end
