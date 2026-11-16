# frozen_string_literal: true

module GoogleSignIn
  # The state of a Google calendar connection (OauthCredentials::SignedState).
  # Each state works once: the callback consumes it.
  class OauthState
    PURPOSE  = "google_calendar"
    TTL      = 1.hour
    ONCE_KEY = "google_oauth_state"

    # email is optional. With an email, the callback accepts only that account.
    # Without one, the person picks any Google account.
    def self.generate_state(user_id:, email: nil)
      OauthCredentials::SignedState.generate(purpose: PURPOSE, ttl: TTL, once_key: ONCE_KEY, user_id: user_id, email: email.presence)
    end

    # Does not use the state up, so it can tell a calendar callback from a sign-in.
    def self.verify_state(state)
      OauthCredentials::SignedState.verify(state, purpose: PURPOSE)
    end

    def self.consume_state(state)
      OauthCredentials::SignedState.consume(state, purpose: PURPOSE, once_key: ONCE_KEY)
    end
  end
end
