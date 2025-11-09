# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "openssl"

# Service for validating and decoding Google RISC security event tokens
class RiscValidationService
  class ValidationError < StandardError; end
  class InvalidTokenError < ValidationError; end
  class InvalidIssuerError < ValidationError; end
  class InvalidAudienceError < ValidationError; end
  class InvalidSignatureError < ValidationError; end
  class KeyNotFoundError < ValidationError; end

  RISC_CONFIGURATION_URL = "https://accounts.google.com/.well-known/risc-configuration"
  CACHE_DURATION = 1.hour

  def initialize
    @risc_config = fetch_risc_configuration
    @jwks = fetch_jwks
  end

  # Validate and decode a security event token
  # Returns a hash with the decoded token payload
  def validate_and_decode(token)
    # Get the key ID from the unverified token header
    unverified_token = JWT.decode(token, nil, false)
    header = unverified_token[1]
    key_id = header["kid"]

    raise KeyNotFoundError, "Token missing key ID (kid) in header" if key_id.blank?

    # Get the public key for this key ID
    public_key = get_public_key(key_id)
    raise KeyNotFoundError, "Public key not found for key ID: #{key_id}" if public_key.nil?

    # Verify and decode the token
    decoded = JWT.decode(
      token,
      public_key,
      true, # Verify signature
      {
        algorithm: "RS256",
        iss: @risc_config["issuer"],
        verify_iss: true,
        verify_aud: true,
        aud: valid_audiences,
        # Don't verify expiration - RISC tokens represent historical events
        verify_expiration: false
      }
    )

    payload = decoded[0]
    ActiveSupport::HashWithIndifferentAccess.new(payload)
  rescue JWT::DecodeError => e
    raise InvalidTokenError, "Invalid token: #{e.message}"
  rescue JWT::VerificationError => e
    raise InvalidSignatureError, "Invalid signature: #{e.message}"
  rescue JWT::InvalidIssuerError => e
    raise InvalidIssuerError, "Invalid issuer: #{e.message}"
  rescue JWT::InvalidAudError => e
    raise InvalidAudienceError, "Invalid audience: #{e.message}"
  end

  # Extract event information from decoded token
  def extract_event_data(decoded_token)
    events = decoded_token["events"] || {}
    event_type = events.keys.first
    event_details = events[event_type] || {}

    subject = event_details["subject"] || {}

    {
      jti: decoded_token["jti"],
      event_type: event_type,
      google_subject: subject["sub"],
      reason: event_details["reason"],
      raw_event_data: decoded_token.to_json,
      iat: decoded_token["iat"],
      state: event_details["state"] # For verification events
    }
  end

  private

  # Fetch the RISC configuration from Google
  def fetch_risc_configuration
    Rails.cache.fetch("risc_configuration", expires_in: CACHE_DURATION) do
      uri = URI.parse(RISC_CONFIGURATION_URL)
      response = Net::HTTP.get_response(uri)

      raise ValidationError, "Failed to fetch RISC configuration: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end
  end

  # Fetch the JSON Web Key Set (JWKS) from Google
  def fetch_jwks
    jwks_uri = @risc_config["jwks_uri"]
    raise ValidationError, "JWKS URI not found in RISC configuration" if jwks_uri.blank?

    Rails.cache.fetch("risc_jwks", expires_in: CACHE_DURATION) do
      uri = URI.parse(jwks_uri)
      response = Net::HTTP.get_response(uri)

      raise ValidationError, "Failed to fetch JWKS: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end
  end

  # Get the public key for a given key ID
  def get_public_key(key_id)
    keys = @jwks["keys"] || []
    key_data = keys.find { |k| k["kid"] == key_id }

    return nil if key_data.nil?

    # Convert JWK to OpenSSL public key
    jwk = JWT::JWK.import(key_data)
    jwk.public_key
  end

  # Get all valid audience values (all OAuth client IDs)
  def valid_audiences
    @valid_audiences ||= begin
      client_ids = []

      # Get from environment variable (comma-separated)
      if ENV["GOOGLE_OAUTH_CLIENT_IDS"].present?
        client_ids += ENV["GOOGLE_OAUTH_CLIENT_IDS"].split(",").map(&:strip)
      end

      # Get from credentials
      if Rails.application.credentials.dig(:google, :client_id).present?
        client_ids << Rails.application.credentials.dig(:google, :client_id)
      end

      # Fallback for development/testing
      if client_ids.empty?
        Rails.logger.warn("No Google OAuth client IDs configured for RISC validation")
        client_ids << "development-client-id"
      end

      client_ids.uniq
    end
  end
end
