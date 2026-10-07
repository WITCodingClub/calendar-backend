# frozen_string_literal: true

class GoogleOauthStateService
  # email is optional. With an email, the callback accepts only that account.
  # Without one, the person picks any Google account.
  def self.generate_state(user_id:, email: nil)
    payload = {
      user_id: user_id,
      email: email.presence,
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
