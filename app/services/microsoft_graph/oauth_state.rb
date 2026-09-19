# frozen_string_literal: true

module MicrosoftGraph
  # The signed state value that ties a Microsoft sign-in back to the person who
  # asked for it. The purpose claim keeps a Google state from being replayed
  # here.
  module OauthState
    PURPOSE = "microsoft_graph_calendar"
    TTL     = 15.minutes

    module_function

    # `placement` is where the person wants the course events: "separate" or
    # "primary". It applies to a first connection only.
    def generate(user_id:, placement: nil)
      payload = {
        user_id:   user_id,
        purpose:   PURPOSE,
        placement: (placement if CourseCalendar::PLACEMENTS.value?(placement.to_s)),
        nonce:     SecureRandom.hex(16),
        exp:       TTL.from_now.to_i
      }.compact

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
