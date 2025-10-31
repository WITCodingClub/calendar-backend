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

    # Find or create user by email
    email_record = Email.find_or_initialize_by(email: email)

    if email_record.new_record?
      # Create a new user if email doesn't exist
      user = User.create!(
        first_name: auth.info.first_name,
        last_name: auth.info.last_name
      )
      email_record.user = user
      email_record.primary = true
      email_record.save!
    else
      user = email_record.user
      # Update user info from OAuth if not set
      user.first_name ||= auth.info.first_name
      user.last_name ||= auth.info.last_name
      user.save! if user.changed?
    end

    # Find or create Google OAuth credential
    credential = user.oauth_credentials.find_or_initialize_by(provider: "google")

    # Update OAuth credentials
    credential.uid = auth.uid
    credential.access_token = auth.credentials.token

    # Only update refresh token if present (it may not be on subsequent authorizations)
    credential.refresh_token = auth.credentials.refresh_token if auth.credentials.refresh_token.present?

    # Store token expiration time
    credential.token_expires_at = Time.at(auth.credentials.expires_at) if auth.credentials.expires_at

    credential.save!

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
