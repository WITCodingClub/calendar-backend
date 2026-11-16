# frozen_string_literal: true

module Api
  # Signs in an API request with the JWT in the Authorization header.
  #
  # Including this module adds no callback. A controller names the actions that
  # need a signed-in user with authenticate_with_token, so the public actions
  # are the ones that do not call it. spec/requests/api/authentication_spec.rb
  # fails for any API route that has no token check and is not on its list of
  # public routes.
  module TokenAuthentication
    extend ActiveSupport::Concern

    included do
      attr_reader :current_user, :current_session
    end

    class_methods do
      # Requires a valid token for the given actions, or for every action when
      # no options are given. Takes the options of before_action (only:,
      # except:). Call it before the other callbacks, so a request with no
      # token gets 401 before a flag check or a record lookup runs.
      def authenticate_with_token(**options)
        before_action :authenticate_user_from_token!, **options
      end
    end

    private

    def authenticate_user_from_token!
      @current_session, code = token_session
      @current_user = user_loaded_by_rack_attack || @current_session.user unless code
      code ||= "AUTH_INVALID" if @current_user.nil?

      if code
        render_error code == "AUTH_REVOKED" ? "Session ended" : "Authentication required", status: :unauthorized, code: code
        return
      end

      @current_session.touch_last_seen!
    end

    # The user of a valid token, or nil. For a public route that reads a
    # per-user flag only: it never answers 401 and never sets current_user,
    # so a bad or ended token is the same as no token.
    def optional_token_user
      token_session.first&.user
    end

    # The active session of the bearer token, as [session, nil], or
    # [nil, code] with the reason there is none. The session is what makes a
    # token revocable: the signature can be perfect and the token still be one
    # the user has since signed out.
    def token_session
      token = extract_token_from_header
      return [ nil, "AUTH_MISSING" ] if token.blank?

      decoded = JsonWebTokenService.decode(token)
      return [ nil, "AUTH_INVALID" ] if decoded.nil?

      session = UserSession.find_by(jti: decoded[:jti])
      session&.active? ? [ session, nil ] : [ nil, "AUTH_REVOKED" ]
    end

    # The Rack::Attack safelist for privileged users loads the user of the
    # token on every API request. Use that record when it is the user of the
    # session, so the request does not load the user a second time (#712).
    def user_loaded_by_rack_attack
      user = request.env[Rack::Attack::JWT_USER_ENV_KEY]
      user if user && user.id == @current_session.user_id
    end

    def extract_token_from_header
      BearerToken.from(request.headers["Authorization"])
    end
  end
end
