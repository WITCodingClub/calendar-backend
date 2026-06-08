# frozen_string_literal: true

module Api
  class UsersController < ApiController
    skip_before_action :authenticate_user_from_token!, only: [:onboard]

    # POST /api/user/onboard
    def onboard
      email          = params[:email]
      preferred_name = params[:preferred_name]

      if email.blank?
        render json: { error: "Email is required" }, status: :bad_request
        return
      end

      if preferred_name.blank?
        render json: { error: "Preferred name is required" }, status: :bad_request
        return
      end

      name_parts = preferred_name.strip.split(" ", 2)
      first_name = name_parts[0]
      last_name  = name_parts[1]

      user = User.find_by(email: email.to_s.strip.downcase) ||
             User.create!(
               email:      email.to_s.strip.downcase,
               first_name: first_name,
               last_name:  last_name,
               password:   SecureRandom.hex(24)
             )

      token = JsonWebTokenService.encode({ user_id: user.id }, nil)

      render json: { pub_id: user.public_id.delete_prefix("usr_"), jwt: token }, status: :ok
    rescue => e
      Rails.logger.error("Error in onboarding user: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: "Failed to onboard user" }, status: :internal_server_error
    end

    # POST /api/user/gcal
    def request_g_cal
      email = params[:email].to_s.strip

      if email.blank?
        render json: { error: "Email is required" }, status: :bad_request
        return
      end

      if current_user.google_credential_for_email(email).present?
        service     = GoogleCalendarService.new(current_user)
        calendar_id = service.create_or_get_course_calendar

        render json: { message: "Email already connected", calendar_id: calendar_id }, status: :ok
      else
        state     = GoogleOauthStateService.generate_state(user_id: current_user.id, email: email)
        oauth_url = "#{request.base_url}/auth/google_oauth2?state=#{CGI.escape(state)}"

        render json: { message: "OAuth required", email: email, oauth_url: oauth_url }, status: :ok
      end
    rescue => e
      Rails.logger.error("Error requesting Google Calendar for user #{current_user.id}: #{e.message}")
      render json: { error: "Failed to request Google Calendar" }, status: :internal_server_error
    end

    # POST /api/user/gcal/add_email
    def add_email_to_g_cal
      email = params[:email].to_s.strip

      if email.blank?
        render json: { error: "Email is required" }, status: :bad_request
        return
      end

      unless current_user.google_credential
        render json: { error: "Complete Google OAuth for at least one email first." }, status: :unprocessable_content
        return
      end

      credential = current_user.oauth_credentials.find_by(email: email, provider: "google")

      unless credential
        state     = GoogleOauthStateService.generate_state(user_id: current_user.id, email: email)
        oauth_url = "#{request.base_url}/auth/google_oauth2?state=#{CGI.escape(state)}"
        render json: { message: "OAuth required for this email", email: email, oauth_url: oauth_url }, status: :ok
        return
      end

      service     = GoogleCalendarService.new(current_user)
      calendar_id = service.create_or_get_course_calendar

      render json: { message: "Calendar shared with email", calendar_id: calendar_id }, status: :ok
    rescue => e
      Rails.logger.error("Error adding email to Google Calendar for user #{current_user.id}: #{e.message}")
      render json: { error: "Failed to add email to Google Calendar" }, status: :internal_server_error
    end

    # DELETE /api/user/gcal/remove_email
    def remove_email_from_g_cal
      email = params[:email].to_s.strip

      if email.blank?
        render json: { error: "Email is required" }, status: :bad_request
        return
      end

      credential = current_user.oauth_credentials.find_by(email: email, provider: "google")

      if credential.nil?
        render json: { error: "Email not found or not associated with Google Calendar" }, status: :not_found
        return
      end

      authorize credential, :destroy?

      google_calendar = current_user.google_credential&.google_calendar

      if google_calendar.nil?
        render json: { error: "No Google Calendar found" }, status: :not_found
        return
      end

      credential.destroy!

      render json: { message: "Email removed from Google Calendar association" }, status: :ok
    rescue => e
      Rails.logger.error("Error removing email from Google Calendar for user #{current_user.id}: #{e.message}")
      render json: { error: "Failed to remove email from Google Calendar" }, status: :internal_server_error
    end

    # GET /api/user/id
    def get_id
      authorize current_user, :show?
      render json: { pub_id: current_user.public_id }, status: :ok
    end

    # GET /api/user/email
    def get_email
      authorize current_user, :show?
      render json: { email: current_user.email }, status: :ok
    end

    # GET /api/user/ics_url
    def get_ics_url
      authorize current_user, :show?
      render json: { ics_url: current_user.cal_url_with_extension }, status: :ok
    end

    # GET /api/user/oauth_credentials
    def list_oauth_credentials
      authorize current_user, :show?

      credentials = current_user.oauth_credentials.includes(:google_calendar).map do |c|
        {
          id:           c.public_id,
          email:        c.email,
          provider:     c.provider,
          has_calendar: c.google_calendar.present?,
          calendar_id:  c.google_calendar&.google_calendar_id,
          created_at:   c.created_at,
          needs_reauth: c.needs_reauth?,
          token_revoked: c.token_revoked?
        }
      end

      render json: { oauth_credentials: credentials }, status: :ok
    end

    # DELETE /api/user/oauth_credentials/:credential_id
    def disconnect_oauth_credential
      credential_id = params[:credential_id]

      if credential_id.blank?
        render json: { error: "credential_id is required" }, status: :bad_request
        return
      end

      credential = find_by_any_id(OauthCredential, credential_id)
      credential = nil unless credential&.user_id == current_user.id

      if credential.nil?
        render json: { error: "OAuth credential not found" }, status: :not_found
        return
      end

      authorize credential, :destroy?

      if current_user.oauth_credentials.one?
        render json: { error: "Cannot disconnect the last OAuth credential." }, status: :unprocessable_content
        return
      end

      credential.destroy!
      render json: { message: "OAuth credential disconnected successfully" }, status: :ok
    rescue => e
      Rails.logger.error("Error disconnecting OAuth credential for user #{current_user.id}: #{e.message}")
      render json: { error: "Failed to disconnect OAuth credential" }, status: :internal_server_error
    end

    # POST /api/user/is_processed
    def is_processed
      authorize current_user, :show?

      term_uid = params[:term_uid]
      if term_uid.blank?
        render json: { error: "term_uid is required" }, status: :bad_request
        return
      end

      term = Term.find_by(uid: term_uid)
      if term.nil?
        render json: { error: "Term not found" }, status: :not_found
        return
      end

      processed = current_user.enrollments.exists?(term_id: term.id)
      render json: { processed: processed }, status: :ok
    end

    # POST /api/user/processed_events
    def get_processed_events_by_term
      authorize current_user, :show?

      term_uid = params[:term_uid]
      if term_uid.blank?
        render json: { error: "term_uid is required" }, status: :bad_request
        return
      end

      term = Term.find_by(uid: term_uid)
      if term.nil?
        render json: { error: "Term not found" }, status: :not_found
        return
      end

      enrollments = current_user
                    .enrollments
                    .where(term_id: term.id)
                    .includes(course: [
                      :faculties,
                      { meeting_times: [:event_preference, { course: :faculties }] }
                    ])

      preference_resolver = PreferenceResolver.new(current_user)
      template_renderer   = CalendarTemplateRenderer.new

      structured_data = enrollments.map do |enrollment|
        EnrolledCourseSerializer.new(
          enrollment,
          term:               term,
          preference_resolver: preference_resolver,
          template_renderer:  template_renderer
        ).as_json
      end

      render json: {
        classes:                structured_data,
        notifications_disabled: current_user.notifications_disabled?
      }, status: :ok
    end

    # GET /api/user/notifications_status
    def notifications_status
      authorize current_user, :show?
      render json: {
        notifications_disabled:       current_user.notifications_disabled?,
        notifications_disabled_until: current_user.notifications_disabled_until
      }, status: :ok
    end

    # POST /api/user/notifications/disable
    def disable_notifications
      authorize current_user, :update?

      duration_provided  = params.key?(:duration) && params[:duration].present?
      duration_seconds   = params[:duration].to_i if duration_provided

      if duration_provided
        if duration_seconds < 0
          render json: { error: "Duration cannot be negative" }, status: :bad_request
          return
        end

        if duration_seconds > 100.years.to_i
          render json: { error: "Duration cannot exceed 100 years" }, status: :bad_request
          return
        end
      end

      if duration_provided && duration_seconds > 0
        current_user.disable_notifications!(duration: duration_seconds.seconds)
      else
        current_user.disable_notifications!
      end

      render json: {
        message:                      "Notifications disabled",
        notifications_disabled:       true,
        notifications_disabled_until: current_user.notifications_disabled_until
      }, status: :ok
    rescue => e
      Rails.logger.error("Error disabling notifications for user #{current_user.id}: #{e.message}")
      render json: { error: "Failed to disable notifications" }, status: :internal_server_error
    end

    # POST /api/user/notifications/enable
    def enable_notifications
      authorize current_user, :update?

      current_user.enable_notifications!
      current_user.update_column(:calendar_needs_sync, true) # rubocop:disable Rails/SkipsModelValidations
      GoogleCalendarSyncJob.perform_later(current_user, force: true)

      render json: {
        message:                      "Notifications enabled",
        notifications_disabled:       false,
        notifications_disabled_until: nil
      }, status: :ok
    rescue => e
      Rails.logger.error("Error enabling notifications for user #{current_user.id}: #{e.message}")
      render json: { error: "Failed to enable notifications" }, status: :internal_server_error
    end
  end
end
