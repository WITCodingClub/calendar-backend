# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "openssl"

class RiscValidationService
  class ValidationError < StandardError; end
  class InvalidTokenError < ValidationError; end
  class InvalidIssuerError < ValidationError; end
  class InvalidAudienceError < ValidationError; end
  class InvalidSignatureError < ValidationError; end
  class KeyNotFoundError < ValidationError; end

  RISC_CONFIGURATION_URL = "https://accounts.google.com/.well-known/risc-configuration"
  CACHE_DURATION = 1.hour
  STALE_BACKUP_DURATION = 7.days

  def initialize
    @risc_config = fetch_risc_configuration
    @jwks = fetch_jwks
  end

  def validate_and_decode(token)
    unverified_token = JWT.decode(token, nil, false)
    header = unverified_token[1]
    key_id = header["kid"]

    raise KeyNotFoundError, "Token missing key ID (kid) in header" if key_id.blank?

    public_key = get_public_key(key_id)
    raise KeyNotFoundError, "Public key not found for key ID: #{key_id}" if public_key.nil?

    decoded = JWT.decode(
      token,
      public_key,
      true,
      {
        algorithm: "RS256",
        iss: @risc_config["issuer"],
        verify_iss: true,
        verify_aud: true,
        aud: valid_audiences,
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
      state: event_details["state"]
    }
  end

  private

  def fetch_risc_configuration
    Rails.cache.fetch("risc_configuration", expires_in: CACHE_DURATION) do
      uri = URI.parse(RISC_CONFIGURATION_URL)
      response = Net::HTTP.get_response(uri)

      raise ValidationError, "Failed to fetch RISC configuration: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      result = JSON.parse(response.body)
      Rails.cache.write("risc_configuration:stale", result, expires_in: STALE_BACKUP_DURATION)
      result
    end
  rescue => e
    stale = Rails.cache.read("risc_configuration:stale")
    if stale.present?
      Rails.logger.warn("[RiscValidationService] Using stale RISC configuration due to fetch error: #{e.message}")
      return stale
    end
    raise
  end

  def fetch_jwks
    jwks_uri = @risc_config["jwks_uri"]
    raise ValidationError, "JWKS URI not found in RISC configuration" if jwks_uri.blank?

    Rails.cache.fetch("risc_jwks", expires_in: CACHE_DURATION) do
      uri = URI.parse(jwks_uri)
      response = Net::HTTP.get_response(uri)

      raise ValidationError, "Failed to fetch JWKS: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      result = JSON.parse(response.body)
      Rails.cache.write("risc_jwks:stale", result, expires_in: STALE_BACKUP_DURATION)
      result
    end
  rescue => e
    stale = Rails.cache.read("risc_jwks:stale")
    if stale.present?
      Rails.logger.warn("[RiscValidationService] Using stale JWKS due to fetch error: #{e.message}")
      return stale
    end
    raise
  end

  def get_public_key(key_id)
    keys = @jwks["keys"] || []
    key_data = keys.find { |k| k["kid"] == key_id }

    return nil if key_data.nil?

    jwk = JWT::JWK.import(key_data)
    jwk.public_key
  end

  def valid_audiences
    @valid_audiences ||= begin
      client_ids = []

      if ENV["GOOGLE_OAUTH_CLIENT_IDS"].present?
        client_ids += ENV["GOOGLE_OAUTH_CLIENT_IDS"].split(",").map(&:strip)
      end

      if Rails.application.credentials.dig(:google, :client_id).present?
        client_ids << Rails.application.credentials.dig(:google, :client_id)
      end

      if client_ids.empty?
        Rails.logger.warn("No Google OAuth client IDs configured for RISC validation")
        client_ids << "development-client-id"
      end

      client_ids.uniq
    end
  end
end
