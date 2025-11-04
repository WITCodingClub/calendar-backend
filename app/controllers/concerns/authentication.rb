# frozen_string_literal: true

module Authentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_user, :user_signed_in?
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def user_signed_in?
    current_user.present?
  end

  def sign_in(user)
    session[:user_id] = user.id
    @current_user = user
  end

  def sign_out
    session.delete(:user_id)
    @current_user = nil
  end

  def authenticate_user!
    return if user_signed_in?

    redirect_to new_user_session_path, alert: "Please sign in to continue."

  end

  def require_admin!
    return if current_user&.admin_access?

    redirect_to unauthorized_path, alert: "You don't have permission to access this page."

  end
end
