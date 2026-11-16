# frozen_string_literal: true

module Api
  # Connects a Google account for calendar sync, and shares the course
  # calendar with more of the user's Google accounts.
  class GoogleCalendarsController < BaseController
    authenticate_with_token

    # The email is optional. Without it, the person picks any Google account in
    # the OAuth screen. With it, only that account is accepted, as in older
    # extension builds.
    def create
      email = params[:email].to_s.strip

      if email.present? && current_user.google_credential_for_email(email).present?
        calendar_id = GoogleCalendar::Provider.new(current_user).ensure_course_calendar

        render json: { message: "email already connected", calendar_id: calendar_id }, status: :ok
      else
        render json: { message: "OAuth required", email: email.presence, oauth_url: connect_url(email.presence) }, status: :ok
      end
    end

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

      credential = current_user.oauth_credentials.google.find_by(email: email)

      unless credential
        render json: { message: "OAuth required for this email", email: email, oauth_url: connect_url(email) }, status: :ok
        return
      end

      calendar_id = GoogleCalendar::Provider.new(current_user).ensure_course_calendar

      render json: { message: "Calendar shared with email", calendar_id: calendar_id }, status: :ok
    end

    def remove_email
      email = params[:email].to_s.strip

      if email.blank?
        render_error "email is required", status: :bad_request
        return
      end

      credential = current_user.oauth_credentials.google.find_by(email: email)

      if credential.nil?
        render_error "email not found or not associated with Google Calendar", status: :not_found
        return
      end

      authorize credential, :destroy?

      course_calendar = CourseCalendar.google.for_user(current_user).first

      if course_calendar.nil?
        render_error "No Google Calendar found", status: :not_found
        return
      end

      unless OauthCredentials::Disconnect.call(credential)
        render_error "Cannot disconnect your last Google account.", status: :unprocessable_content
        return
      end

      render json: { message: "email removed from Google Calendar association" }, status: :ok
    end

    private

    def connect_url(email)
      request.base_url + GoogleCalendar::Provider.connect_path(current_user, email: email)
    end
  end
end
