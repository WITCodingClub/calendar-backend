# frozen_string_literal: true

class AuthController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:google]

  def google
    auth = request.env["omniauth.auth"]
    raise "Missing omniauth.auth" unless auth

    # Check if this is a calendar OAuth flow (has our custom JWT state parameter)
    # OmniAuth adds its own state for CSRF, so we need to check if it's a valid JWT
    if is_calendar_oauth_flow?
      handle_calendar_oauth(auth)
    else
      handle_admin_login(auth)
    end
  rescue => e
    Rails.logger.error("Google OAuth error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))

    if is_calendar_oauth_flow?
      redirect_to "/oauth/failure?error=#{CGI.escape(e.message)}"
    else
      redirect_to new_user_session_path, alert: "Failed to connect with Google. Please try again."
    end
  end

  private

  def is_calendar_oauth_flow?
    return false if params[:state].blank?

    # Try to verify the state as a JWT - if it succeeds, it's our calendar OAuth flow
    GoogleOauthStateService.verify_state(params[:state]).present?
  rescue
    # If verification fails, it's not our JWT state (just OmniAuth's CSRF state)
    false
  end

  def handle_calendar_oauth(auth)
    # Verify and decode state parameter
    state_data = GoogleOauthStateService.verify_state(params[:state])
    unless state_data
      raise "Invalid or expired state parameter"
    end

    user = User.find(state_data["user_id"])
    target_email = state_data["email"]

    # Verify the OAuth email matches the target email
    unless auth.info.email == target_email
      raise "OAuth email (#{auth.info.email}) does not match expected email (#{target_email})"
    end

    # Create or update OAuth credential for this specific email
    credential = user.oauth_credentials.find_or_initialize_by(
      provider: "google",
      email: target_email
    )

    credential.uid = auth.uid
    credential.access_token = auth.credentials.token
    credential.refresh_token = auth.credentials.refresh_token if auth.credentials.refresh_token.present?
    credential.token_expires_at = Time.zone.at(auth.credentials.expires_at) if auth.credentials.expires_at
    credential.save!

    # Create calendar if it doesn't exist and share with this email
    service = GoogleCalendarService.new(user)
    calendar_id = service.create_or_get_course_calendar

    # Note: Don't sync here - user has no enrollments yet!
    # The sync will be triggered by CourseProcessorService after enrollments are created.

    # Redirect to success page
    redirect_to "/oauth/success?email=#{CGI.escape(target_email)}&calendar_id=#{calendar_id}"
  end

  def handle_admin_login(auth)
    email = auth.info.email

    # Validate that the email is from @wit.edu domain
    unless email&.match?(/@wit\.edu\z/i)
      redirect_to new_user_session_path, alert: "Only @wit.edu email addresses are allowed."
      return
    end

    # Find existing user (no longer auto-create accounts)
    user = User.find_by(email: email)

    # Check if user exists and is an admin
    unless user&.admin_access?
      redirect_to new_user_session_path, alert: "Sign-in is restricted to administrators only."
      return
    end

    # Update user info from OAuth if not set
    user.first_name ||= auth.info.first_name
    user.last_name ||= auth.info.last_name
    user.save! if user.changed?

    # Find or create Google OAuth credential
    credential = user.oauth_credentials.find_or_initialize_by(provider: "google", email: email)

    # Update OAuth credentials
    credential.uid = auth.uid
    credential.access_token = auth.credentials.token
    credential.refresh_token = auth.credentials.refresh_token if auth.credentials.refresh_token.present?
    credential.token_expires_at = Time.zone.at(auth.credentials.expires_at) if auth.credentials.expires_at
    credential.save!

    # Sign in the user
    sign_in(user)

    redirect_to after_sign_in_path, notice: "Successfully signed in with Google."
  end

  def after_sign_in_path
    if current_user.admin_access?
      admin_root_path
    else
      dashboard_path
    end
  end

end
