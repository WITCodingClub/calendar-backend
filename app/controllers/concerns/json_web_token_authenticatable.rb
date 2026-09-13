# frozen_string_literal: true

module JsonWebTokenAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_user_from_token!
    attr_reader :current_user, :current_session
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
