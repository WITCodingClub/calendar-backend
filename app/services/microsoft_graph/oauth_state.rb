# frozen_string_literal: true

module MicrosoftGraph
  # The state of a Microsoft calendar connection (OauthCredentials::SignedState).
  # The controller keeps a nonce in the session and checks it on the callback
  # (Auth::MicrosoftGraphController), so the state itself is not one-use.
  module OauthState
    PURPOSE = "microsoft_graph_calendar"
    TTL     = 15.minutes

    module_function

    # `placement` is where the person wants the course events: "separate" or
    # "primary". It applies to a first connection only.
    def generate(user_id:, placement: nil)
      placement = placement.to_s.presence_in(CourseCalendar::PLACEMENTS.values)
      OauthCredentials::SignedState.generate(purpose: PURPOSE, ttl: TTL, **{ user_id: user_id, placement: placement }.compact)
    end

    def verify(state)
      OauthCredentials::SignedState.verify(state, purpose: PURPOSE)
    end
  end
end
