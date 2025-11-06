# frozen_string_literal: true

module Api
  class UsersController < ApplicationController
    include JsonWebTokenAuthenticatable
    include FeatureFlagGated

    skip_before_action :verify_authenticity_token
    skip_before_action :authenticate_user_from_token!, only: [:onboard]
    skip_before_action :check_beta_access, only: [:onboard]

    def onboard
      #   takes email as it's one param
      email = params[:email]

      if email.blank?
        render json: { error: "Email is required" }, status: :bad_request
        return
      end

      user = User.find_or_create_by_email(email)

      beta_access = Flipper.enabled?(Features::V1, user)

      # return JSON with a jwt token for the user. this token should be signed, and never expire
      token = JsonWebTokenService.encode({ user_id: user.id }, nil) # nil expiration for never expiring

      render json: {
        beta_access: beta_access,
        jwt: token
      }, status: :ok
    rescue => e
      Rails.logger.error("Error in onboarding user: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: "Failed to onboard user" }, status: :internal_server_error

    end

    def get_email

      email = current_user.primary_email

      render json: { email: email}, status: :ok
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

      # Check if user has completed OAuth for at least one email
      if current_user.google_credential.nil?
        render json: {
          error: "You must complete Google OAuth for at least one email before adding calendar access. Please use the /api/user/gcal endpoint first."
        }, status: :unprocessable_entity
        return
      end

      # trigger function to ensure calendar is shared with that email synchronously
      service = GoogleCalendarService.new(current_user)
      calendar_id = service.create_or_get_course_calendar
      service.share_calendar_with_email(calendar_id, email)

      # Trigger calendar sync to update the newly shared calendar
      GoogleCalendarSyncJob.perform_later(current_user)

      render json: { message: "Calendar shared with email", calendar_id: calendar_id }, status: :ok
    rescue => e
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

      # Check if user has a calendar to remove access from
      calendar_id = current_user.google_course_calendar_id
      if calendar_id.blank?
        render json: { error: "No Google Calendar found to remove access from" }, status: :not_found
        return
      end

      # Remove g_cal association
      email_record.g_cal = false
      email_record.save!

      service = GoogleCalendarService.new(current_user)
      service.unshare_calendar_with_email(calendar_id, email)

      render json: { message: "Email removed from Google Calendar association" }, status: :ok
    rescue => e
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

        # Trigger calendar sync to populate the calendar with course events
        GoogleCalendarSyncJob.perform_later(current_user)

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
    rescue => e
      Rails.logger.error("Error requesting Google Calendar for user #{current_user.id}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: "Failed to request Google Calendar" }, status: :internal_server_error
    end


  end
end
