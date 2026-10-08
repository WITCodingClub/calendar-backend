# frozen_string_literal: true

# The signed state value that ties a Google calendar connection back to the
# person who asked for it.
#
# Each state works once: its nonce is kept in Rails.cache until the callback
# consumes it. The purpose claim keeps other signed tokens (a Microsoft state,
# for example) from being used here.
class GoogleOauthStateService
  PURPOSE = "google_calendar"
  TTL     = 1.hour

  # email is optional. With an email, the callback accepts only that account.
  # Without one, the person picks any Google account.
  def self.generate_state(user_id:, email: nil)
    nonce = SecureRandom.hex(16)
    Rails.cache.write(nonce_key(nonce), user_id, expires_in: TTL)

    payload = {
      user_id: user_id,
      email: email.presence,
      purpose: PURPOSE,
      nonce: nonce,
      exp: TTL.from_now.to_i
    }

    JWT.encode(payload, Rails.application.secret_key_base, "HS256")
  end

  # Checks the signature, the expiry and the purpose. It does not use the
  # state up, so it can tell a calendar callback from a sign-in.
  def self.verify_state(state)
    return nil if state.blank?

    payload = JWT.decode(state, Rails.application.secret_key_base, true, algorithm: "HS256")[0]
    payload["purpose"] == PURPOSE ? payload : nil
  rescue JWT::DecodeError
    nil
  end

  # Returns the payload once. A second call with the same state returns nil.
  def self.consume_state(state)
    payload = verify_state(state)
    return nil unless payload && payload["nonce"].present?
    return nil unless Rails.cache.delete(nonce_key(payload["nonce"]))

    payload
  end

  def self.nonce_key(nonce)
    "google_oauth_state:#{nonce}"
  end
  private_class_method :nonce_key
end
