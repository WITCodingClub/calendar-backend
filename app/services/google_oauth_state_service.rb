# frozen_string_literal: true

class GoogleOauthStateService
  def self.generate_state(user_id:, email:)
    payload = {
      user_id: user_id,
      email: email,
      nonce: SecureRandom.hex(16),
      exp: 1.hour.from_now.to_i
    }

    JWT.encode(payload, Rails.application.secret_key_base, "HS256")
  end

  def self.verify_state(state)
    JWT.decode(state, Rails.application.secret_key_base, true, algorithm: "HS256")[0]
  rescue JWT::DecodeError, JWT::ExpiredSignature
    nil
  end
end
