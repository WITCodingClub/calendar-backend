class AuthController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:google]

  def google
    auth = request.env['omniauth.auth']
    raise "Missing omniauth.auth" unless auth

    email = auth.info.email

    # Validate that the email is from @wit.edu domain
    unless email&.match?(/@wit\.edu\z/i)
      redirect_to new_user_session_path, alert: 'Only @wit.edu email addresses are allowed.'
      return
    end

    # Find or create user
    user = User.find_or_initialize_by(email: email)

    # Update user info from OAuth
    user.first_name ||= auth.info.first_name
    user.last_name ||= auth.info.last_name

    # Update Google OAuth credentials
    user.google_uid = auth.uid
    user.google_access_token = auth.credentials.token

    # Only update refresh token if present (it may not be on subsequent authorizations)
    user.google_refresh_token = auth.credentials.refresh_token if auth.credentials.refresh_token.present?

    # Store token expiration time
    user.google_token_expires_at = Time.at(auth.credentials.expires_at) if auth.credentials.expires_at

    user.save!

    # Sign in the user using the existing authentication system
    sign_in(user)

    redirect_to after_sign_in_path, notice: 'Successfully connected with Google.'
  rescue => e
    Rails.logger.error("Google OAuth error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    redirect_to new_user_session_path, alert: 'Failed to connect with Google. Please try again.'
  end

  private

  def after_sign_in_path
    if current_user.admin_access?
      admin_root_path
    else
      dashboard_path
    end
  end
end
