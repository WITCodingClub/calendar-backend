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
      token = extract_token_from_header

      if token.blank?
        render json: { success: false, error: "Authentication required", code: "AUTH_MISSING" }, status: :unauthorized
        return
      end

      decoded = JsonWebTokenService.decode(token)

      if decoded.nil?
        render json: { success: false, error: "Authentication required", code: "AUTH_INVALID" }, status: :unauthorized
        return
      end

      # The session is what makes a token revocable: the signature can be perfect
      # and the token still be one the user has since signed out.
      @current_session = UserSession.find_by(jti: decoded[:jti])

      if @current_session.nil? || !@current_session.active?
        render json: { success: false, error: "Session ended", code: "AUTH_REVOKED" }, status: :unauthorized
        return
      end

      @current_user = @current_session.user

      if @current_user.nil?
        render json: { success: false, error: "Authentication required", code: "AUTH_INVALID" }, status: :unauthorized
        return
      end

      @current_session.touch_last_seen!
    end

    def extract_token_from_header
      auth_header = request.headers["Authorization"]
      return nil unless auth_header

      auth_header.gsub(/^Bearer\s+/, "")
    end
  end
end
