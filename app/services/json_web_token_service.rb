# frozen_string_literal: true

class JsonWebTokenService
  SECRET_KEY = Rails.application.credentials.jwt_secret_key ||
               Rails.application.credentials.secret_key_base ||
               Rails.application.secret_key_base

  # Default lifetime for API tokens. Every token gets an expiry — a token
  # without an `exp` claim would never expire, which is a security hazard.
  DEFAULT_TTL = 14.days

  def self.encode(payload, exp = DEFAULT_TTL.from_now)
    raise ArgumentError, "JWT expiry is required" if exp.blank?

    payload = payload.dup
    payload[:exp] = exp.to_i
    JWT.encode(payload, SECRET_KEY)
  end

  # Verifies signature (HS256) and expiration. Returns nil for any invalid,
  # tampered, or expired token.
  def self.decode(token)
    decoded = JWT.decode(token, SECRET_KEY, true, { algorithm: "HS256" })[0]
    ActiveSupport::HashWithIndifferentAccess.new(decoded)
  rescue JWT::DecodeError, JWT::ExpiredSignature
    nil
  end
end
