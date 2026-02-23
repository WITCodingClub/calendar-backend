# frozen_string_literal: true

module JsonWebTokenAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_user_from_token!
    attr_reader :current_user
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

    @current_user = User.find_by(id: decoded[:user_id])

    return unless @current_user.nil?

    render json: { success: false, error: "Authentication required", code: "AUTH_INVALID" }, status: :unauthorized

  end

  def extract_token_from_header
    auth_header = request.headers["Authorization"]
    return nil unless auth_header

    # Support both "Bearer TOKEN" and "TOKEN" formats
    auth_header.gsub(/^Bearer\s+/, "")
  end
end
