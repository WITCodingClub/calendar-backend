# frozen_string_literal: true

class GoogleOauthStateService
  # Generate a signed state parameter for OAuth flow
  # Contains: user_id, email, nonce
  def self.generate_state(user_id:, email:)
    payload = {
      user_id: user_id,
      email: email,
      nonce: SecureRandom.hex(16),
      exp: 1.hour.from_now.to_i
    }

    JWT.encode(payload, Rails.application.secret_key_base, "HS256")
  end

  # Verify and decode the state parameter
  # Returns hash with user_id and email, or nil if invalid
  def self.verify_state(state)
    JWT.decode(state, Rails.application.secret_key_base, true, algorithm: "HS256")[0]
  rescue JWT::DecodeError, JWT::ExpiredSignature
    nil
  end

end
