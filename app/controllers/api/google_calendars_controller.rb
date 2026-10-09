# frozen_string_literal: true

module Api
  # Connects a Google account for calendar sync, and shares the course
  # calendar with more of the user's Google accounts.
  class GoogleCalendarsController < BaseController
    authenticate_with_token

    # POST /api/user/google_calendar
    #
    # The email is optional. Without it, the person picks any Google account in
    # the OAuth screen. With it, only that account is accepted, as in older
    # extension builds.
    def create
      email = params[:email].to_s.strip

      if email.present? && current_user.google_credential_for_email(email).present?
        service     = GoogleCalendar::Provider.new(current_user)
        calendar_id = service.create_or_get_course_calendar

        render json: { message: "email already connected", calendar_id: calendar_id }, status: :ok
      else
        state     = GoogleSignIn::OauthState.generate_state(user_id: current_user.id, email: email.presence)
        oauth_url = "#{request.base_url}/auth/google_oauth2?state=#{CGI.escape(state)}"

        render json: { message: "OAuth required", email: email.presence, oauth_url: oauth_url }, status: :ok
      end
    rescue => e
      Rails.logger.error("Error requesting Google Calendar for user #{current_user.id}: #{e.message}")
      render_error "Failed to request Google Calendar", status: :internal_server_error
    end

    # POST /api/user/google_calendar/emails
    def add_email
      email = params[:email].to_s.strip

      if email.blank?
        render_error "email is required", status: :bad_request
        return
      end

      unless current_user.google_credential
        render_error "Complete Google OAuth for at least one email first.", status: :unprocessable_content
        return
      end

      credential = current_user.oauth_credentials.find_by(email: email, provider: "google")

      unless credential
        state     = GoogleSignIn::OauthState.generate_state(user_id: current_user.id, email: email)
        oauth_url = "#{request.base_url}/auth/google_oauth2?state=#{CGI.escape(state)}"
        render json: { message: "OAuth required for this email", email: email, oauth_url: oauth_url }, status: :ok
        return
      end

      service     = GoogleCalendar::Provider.new(current_user)
      calendar_id = service.create_or_get_course_calendar

      render json: { message: "Calendar shared with email", calendar_id: calendar_id }, status: :ok
    rescue => e
      Rails.logger.error("Error adding email to Google Calendar for user #{current_user.id}: #{e.message}")
      render_error "Failed to add email to Google Calendar", status: :internal_server_error
    end

    # DELETE /api/user/google_calendar/emails
    def remove_email
      email = params[:email].to_s.strip

      if email.blank?
        render_error "email is required", status: :bad_request
        return
      end

      credential = current_user.oauth_credentials.find_by(email: email, provider: "google")

      if credential.nil?
        render_error "email not found or not associated with Google Calendar", status: :not_found
        return
      end

      authorize credential, :destroy?

      course_calendar = current_user.google_credential&.course_calendar

      if course_calendar.nil?
        render_error "No Google Calendar found", status: :not_found
        return
      end

      credential.destroy!

      render json: { message: "email removed from Google Calendar association" }, status: :ok
    rescue => e
      Rails.logger.error("Error removing email from Google Calendar for user #{current_user.id}: #{e.message}")
      render_error "Failed to remove email from Google Calendar", status: :internal_server_error
    end
  end
end
