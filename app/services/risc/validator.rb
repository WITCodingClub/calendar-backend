# frozen_string_literal: true

module Risc
  class Validator
    class ValidationError < StandardError; end
    class InvalidTokenError < ValidationError; end
    class KeyNotFoundError < ValidationError; end
    # Google's config or JWKS could not be fetched. This says nothing about the
    # token, so it is not a ValidationError: the job retries it and does not
    # discard the event.
    class FetchError < StandardError; end

    RISC_CONFIGURATION_URL = "https://accounts.google.com/.well-known/risc-configuration"
    CACHE_DURATION = 1.hour
    STALE_BACKUP_DURATION = 7.days
    READ_TIMEOUT = 10
    # A token with an unknown kid makes one JWKS refetch. This limits how often
    # a flood of forged kids can make us call Google.
    JWKS_REFETCH_COOLDOWN = 1.minute

    def initialize
      @risc_config = fetch_risc_configuration
      @jwks = fetch_jwks
    end

    def validate_and_decode(token)
      unverified_token = JWT.decode(token, nil, false)
      header = unverified_token[1]
      key_id = header["kid"]

      raise KeyNotFoundError, "Token missing key ID (kid) in header" if key_id.blank?

      public_key = get_public_key(key_id) || refetch_public_key(key_id)
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
          aud: GoogleCalendar.client_ids,
          verify_expiration: false
        }
      )

      payload = decoded[0]
      ActiveSupport::HashWithIndifferentAccess.new(payload)
    # A bad signature, issuer, or audience is a JWT::DecodeError too.
    rescue JWT::DecodeError => e
      raise InvalidTokenError, "Invalid token: #{e.message}"
    end

    def extract_event_data(decoded_token)
      events = decoded_token["events"] || {}
      event_type = events.keys.first
      event_details = events[event_type] || {}

      subject = event_details["subject"] || {}
      # A token-revoked event names a token in `subject`. The OpenID OAuth
      # event types draft puts the account, when it is sent, in `token_subject`.
      token_subject = event_details["token_subject"] || {}

      {
        jti: decoded_token["jti"],
        event_type: event_type,
        google_subject: subject["sub"].presence || token_subject["sub"].presence,
        token_identifier: token_identifier(subject),
        reason: event_details["reason"],
        raw_event_data: decoded_token.to_json,
        iat: decoded_token["iat"],
        state: event_details["state"]
      }
    end

    private

    # The token fields of an OAuth token subject, or nil when the subject names
    # no token.
    def token_identifier(subject)
      return nil if subject["token"].blank?

      {
        token_type: subject["token_type"],
        algorithm: subject["token_identifier_alg"],
        token: subject["token"]
      }
    end

    def get_json(url, name)
      response = HttpFetcher.connection(timeout: READ_TIMEOUT).get(url)
      raise FetchError, "Failed to fetch #{name}: #{response.status}" unless response.success?

      JSON.parse(response.body)
    rescue Faraday::Error => e
      raise FetchError, "Failed to fetch #{name}: #{e.message}"
    end

    def fetch_risc_configuration
      Rails.cache.fetch("risc_configuration", expires_in: CACHE_DURATION) do
        result = get_json(RISC_CONFIGURATION_URL, "RISC configuration")
        Rails.cache.write("risc_configuration:stale", result, expires_in: STALE_BACKUP_DURATION)
        result
      end
    rescue => e
      stale = Rails.cache.read("risc_configuration:stale")
      if stale.present?
        Rails.error.report(e, handled: true, context: { fallback: "stale_risc_configuration" })
        return stale
      end
      raise
    end

    def fetch_jwks
      jwks_uri = @risc_config["jwks_uri"]
      raise ValidationError, "JWKS URI not found in RISC configuration" if jwks_uri.blank?

      Rails.cache.fetch("risc_jwks", expires_in: CACHE_DURATION) { download_jwks }
    rescue => e
      stale = Rails.cache.read("risc_jwks:stale")
      if stale.present?
        Rails.error.report(e, handled: true, context: { fallback: "stale_jwks" })
        return stale
      end
      raise
    end

    def download_jwks
      result = get_json(@risc_config["jwks_uri"], "JWKS")
      Rails.cache.write("risc_jwks:stale", result, expires_in: STALE_BACKUP_DURATION)
      result
    end

    # Google rotates its signing keys. The cached JWKS can miss a new key for up
    # to an hour, so an unknown kid gets one fresh fetch before the token is
    # rejected. A failed fetch raises FetchError and does not fall back to the
    # stale copy, because that copy lacks the key too.
    def refetch_public_key(key_id)
      if Rails.cache.write("risc_jwks:refetched", true, expires_in: JWKS_REFETCH_COOLDOWN, unless_exist: true)
        @jwks = download_jwks
        Rails.cache.write("risc_jwks", @jwks, expires_in: CACHE_DURATION)
      else
        @jwks = fetch_jwks
      end

      get_public_key(key_id)
    end

    def get_public_key(key_id)
      keys = @jwks["keys"] || []
      key_data = keys.find { |k| k["kid"] == key_id }

      return nil if key_data.nil?

      jwk = JWT::JWK.import(key_data)
      jwk.public_key
    end
  end
end
