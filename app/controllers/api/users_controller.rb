module Api
  class UsersController < ApplicationController
    include JsonWebTokenAuthenticatable

    skip_before_action :verify_authenticity_token
    skip_before_action :authenticate_user_from_token!, only: [:onboard]

    def onboard
      #   takes email as it's one param
      email = params[:email]

      if email.blank?
        render json: { error: "Email is required" }, status: :bad_request
        return
      end

      user = User.find_or_create_by_email(email)

      # return JSON with a jwt token for the user. this token should be signed, and never expire
      token = JsonWebTokenService.encode({ user_id: user.id }, nil) # nil expiration for never expiring

      render json: { jwt: token }, status: :ok
    rescue StandardError => e
      Rails.logger.error("Error in onboarding user: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: "Failed to onboard user" }, status: :internal_server_error

    end

    def add_email_to_g_cal
      email = params[:email]

      if email.blank?
        render json: { error: "Email is required" }, status: :bad_request
        return
      end

      email = email.to_s.strip
      # Create/update Email record with g_cal = true
      email_record = current_user.emails.find_or_initialize_by(email: email)
      email_record.g_cal = true
      email_record.save!

      # trigger function to ensure calendar is shared with that email synchronously
      service = GoogleCalendarService.new(current_user)
      calendar_id = service.create_or_get_course_calendar
      service.share_calendar_with_email(calendar_id, email.id)
      render json: { message: "Calendar shared with email", calendar_id: calendar_id }, status: :ok
    rescue StandardError => e
      Rails.logger.error("Error adding email to Google Calendar for user #{current_user.id}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: "Failed to add email to Google Calendar" }, status: :internal_server_error

    end

    def remove_email_from_g_cal
      email = params[:email]

      if email.blank?
        render json: { error: "Email is required" }, status: :bad_request
        return
      end

      email = email.to_s.strip
      email_record = current_user.emails.find_by(email: email)

      if email_record.nil? || !email_record.g_cal
        render json: { error: "Email not found or not associated with Google Calendar" }, status: :not_found
        return
      end

      # Remove g_cal association
      email_record.g_cal = false
      email_record.save!

      service = GoogleCalendarService.new(current_user)
      calendar_id = current_user.google_course_calendar_id
      service.unshare_calendar_with_email(calendar_id, email_record.id)

      render json: { message: "Email removed from Google Calendar association" }, status: :ok
    rescue StandardError => e
      Rails.logger.error("Error removing email from Google Calendar for user #{current_user.id}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: "Failed to remove email from Google Calendar" }, status: :internal_server_error
    end

    def request_g_cal
      email = params[:email]

      if email.blank?
        render json: { error: "Email is required" }, status: :bad_request
        return
      end

      email = email.to_s.strip

      # Create/update Email record with g_cal = true
      email_record = current_user.emails.find_or_initialize_by(email: email)
      email_record.g_cal = true
      email_record.save!

      # Check if this email already has OAuth credentials
      if current_user.google_credential_for_email(email).present?
        # Email has credentials, ensure calendar is created and shared
        service = GoogleCalendarService.new(current_user)
        calendar_id = service.create_or_get_course_calendar

        render json: {
          message: "Email already connected",
          calendar_id: calendar_id
        }, status: :ok
      else
        # Generate state parameter
        state = GoogleOauthStateService.generate_state(
          user_id: current_user.id,
          email: email
        )

        # Build OAuth URL with full path
        oauth_url = "#{request.base_url}/auth/google_oauth2?state=#{CGI.escape(state)}"

        render json: {
          message: "OAuth required",
          email: email,
          oauth_url: oauth_url
        }, status: :ok
      end
    rescue StandardError => e
      Rails.logger.error("Error requesting Google Calendar for user #{current_user.id}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: "Failed to request Google Calendar" }, status: :internal_server_error
    end


  end
end
