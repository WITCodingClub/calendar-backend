# frozen_string_literal: true

class AuthController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:google]

  def google
    auth = request.env["omniauth.auth"]
    raise "Missing omniauth.auth" unless auth

    if calendar_oauth_flow?
      handle_calendar_oauth(auth)
    else
      handle_user_login(auth)
    end
  rescue => e
    Rails.logger.error("Google OAuth error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))

    if calendar_oauth_flow?
      redirect_to "/oauth/failure?error=#{CGI.escape(e.message)}"
    else
      redirect_to new_user_session_path, alert: "Failed to connect with Google. Please try again."
    end
  end

  private

  def calendar_oauth_flow?
    return false if params[:state].blank?

    GoogleOauthStateService.verify_state(params[:state]).present?
  rescue
    false
  end

  def handle_calendar_oauth(auth)
    state_data    = GoogleOauthStateService.verify_state(params[:state])
    raise "Invalid or expired state parameter" unless state_data

    user         = User.find(state_data["user_id"])
    target_email = state_data["email"]

    unless auth.info.email == target_email
      raise "OAuth email (#{auth.info.email}) does not match expected email (#{target_email})"
    end

    credential = user.oauth_credentials.find_or_initialize_by(provider: "google", email: target_email)
    credential.uid             = auth.uid
    credential.access_token    = auth.credentials.token
    credential.refresh_token   = auth.credentials.refresh_token if auth.credentials.refresh_token.present?
    credential.token_expires_at = Time.zone.at(auth.credentials.expires_at) if auth.credentials.expires_at
    credential.save!

    service     = GoogleCalendarService.new(user)
    calendar_id = service.create_or_get_course_calendar

    GoogleCalendarSyncJob.perform_later(user, force: false) if user.enrollments.any?

    redirect_to "/oauth/success?email=#{CGI.escape(target_email)}&calendar_id=#{calendar_id}"
  end

  def handle_user_login(auth)
    email = auth.info.email

    unless email&.match?(/@wit\.edu\z/i)
      redirect_to new_user_session_path, alert: "Only @wit.edu email addresses are allowed."
      return
    end

    user = User.find_or_initialize_by(email: email)

    if user.new_record?
      user.first_name = auth.info.first_name.presence || email.split("@").first
      user.last_name  = auth.info.last_name.presence || ""
      user.password   = SecureRandom.hex(24)
      user.skip_confirmation!
      user.save!
    else
      user.first_name ||= auth.info.first_name
      user.last_name  ||= auth.info.last_name
      user.skip_confirmation! unless user.confirmed?
      user.save! if user.changed?
    end

    # Only persist the Google credential when calendar scopes were granted
    # (minimal-scope logins omit refresh_token and have no calendar scope).
    granted_scopes = auth.credentials&.token && auth.extra&.raw_info&.fetch("granted_scopes", "")
    if granted_scopes.to_s.include?("calendar")
      credential = user.oauth_credentials.find_or_initialize_by(provider: "google", email: email)
      credential.uid              = auth.uid
      credential.access_token     = auth.credentials.token
      credential.refresh_token    = auth.credentials.refresh_token if auth.credentials.refresh_token.present?
      credential.token_expires_at = Time.zone.at(auth.credentials.expires_at) if auth.credentials.expires_at
      credential.save!
    end

    sign_in(:user, user)

    redirect_to user.admin_access? ? admin_root_path : dashboard_root_path,
                notice: "Welcome, #{user.first_name}!"
  end
end
