# frozen_string_literal: true

class JsonWebTokenService
  SECRET_KEY = Rails.application.credentials.jwt_secret_key ||
               Rails.application.credentials.secret_key_base ||
               Rails.application.secret_key_base

  # Default lifetime for API tokens. Every token gets an expiry — a token
  # without an `exp` claim would never expire, which is a security hazard.
  DEFAULT_TTL = 90.days

  # Every token carries a jti so it can be matched to a UserSession and taken
  # away again. Without one a token is valid until it expires, and the only way
  # to stop it is rotating the signing key, which signs out everybody.
  def self.encode(payload, exp = DEFAULT_TTL.from_now)
    raise ArgumentError, "JWT expiry is required" if exp.blank?

    payload = payload.dup
    payload[:exp] = exp.to_i
    payload[:jti] ||= SecureRandom.uuid
    JWT.encode(payload, SECRET_KEY)
  end

  # Mints a token and the session that can revoke it.
  def self.issue(user:, source:, request: nil, passkey: nil, exp: DEFAULT_TTL.from_now)
    jti   = SecureRandom.uuid
    token = encode({ user_id: user.id, jti: jti }, exp)

    UserSession.create!(
      user:         user,
      jti:          jti,
      source:       source,
      passkey:      passkey,
      user_agent:   request&.user_agent.to_s.first(500).presence,
      device_label: UserSession.label_for(request&.user_agent),
      ip_address:   request&.remote_ip,
      expires_at:   exp
    )

    token
  end

  # Verifies signature (HS256) and expiration. Returns nil for any invalid,
  # tampered, or expired token.
  #
  # `exp` and `jti` are both required, not merely honoured when present. The old
  # onboarding endpoint minted tokens with no expiry for any account an attacker
  # named, and a token with no `exp` never expires — so closing that endpoint
  # would leave every already-minted token valid forever. `jti` is what ties a
  # token to a revocable session; one without it could never be taken away.
  # Refusing both retires the whole legacy batch, and their holders sign in
  # again through the verified flow.
  def self.decode(token)
    decoded = JWT.decode(token, SECRET_KEY, true, { algorithm: "HS256", required_claims: [ "exp", "jti" ] })[0]
    ActiveSupport::HashWithIndifferentAccess.new(decoded)
  rescue JWT::DecodeError, JWT::ExpiredSignature
    nil
  end
end
