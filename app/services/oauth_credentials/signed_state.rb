# frozen_string_literal: true

module OauthCredentials
  # The signed OAuth state value that ties an account connection back to the
  # person who asked for it. Each flow names its purpose, so the state of one
  # flow is never accepted by another, and its lifetime.
  #
  # A flow that checks the state only through the signature can use it until it
  # expires. A one-use flow (once_key:) keeps the nonce in Rails.cache until
  # .consume takes it, so a second use of the same state fails.
  module SignedState
    module_function

    def generate(purpose:, ttl:, once_key: nil, **claims)
      nonce = SecureRandom.hex(16)
      Rails.cache.write("#{once_key}:#{nonce}", true, expires_in: ttl) if once_key

      payload = claims.merge(purpose: purpose, nonce: nonce, exp: ttl.from_now.to_i)
      JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    end

    # Checks the signature, the expiry and the purpose, and returns the payload
    # or nil. It does not use the state up.
    def verify(state, purpose:)
      return nil if state.blank?

      payload = JWT.decode(state, Rails.application.secret_key_base, true, algorithm: "HS256").first
      payload["purpose"] == purpose ? payload : nil
    rescue JWT::DecodeError
      nil
    end

    # Returns the payload once. A second call with the same state returns nil.
    def consume(state, purpose:, once_key:)
      payload = verify(state, purpose: purpose)
      return nil unless payload && payload["nonce"].present?
      return nil unless Rails.cache.delete("#{once_key}:#{payload['nonce']}")

      payload
    end
  end
end
