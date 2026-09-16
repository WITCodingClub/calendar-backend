# frozen_string_literal: true

module MicrosoftGraph
  # The signed state value that ties a Microsoft sign-in back to the person who
  # asked for it. The purpose claim keeps a Google state from being replayed
  # here.
  module OauthState
    PURPOSE = "microsoft_graph_calendar"
    TTL     = 15.minutes

    module_function

    def generate(user_id:)
      payload = {
        user_id: user_id,
        purpose: PURPOSE,
        nonce:   SecureRandom.hex(16),
        exp:     TTL.from_now.to_i
      }

      JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    end

    def verify(state)
      return nil if state.blank?

      payload = JWT.decode(state, Rails.application.secret_key_base, true, algorithm: "HS256").first
      payload["purpose"] == PURPOSE ? payload : nil
    rescue JWT::DecodeError
      nil
    end
  end
end
