# frozen_string_literal: true

module Api
  class UsersController < ApiController
    include ApplicationHelper

    skip_before_action :authenticate_user_from_token!, only: [:onboard]
    skip_before_action :check_beta_access, only: [:onboard, :get_email]

    def onboard
      #   takes email as it's one param
      email = params[:email]
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
      last_name = name_parts[1] if name_parts.length > 1

      user = User.find_or_create_by_email(email, first_name, last_name)

      beta_access = Flipper.enabled?(FlipperFlags::V1, user)

      # return JSON with a jwt token for the user. this token should be signed, and never expire
      token = JsonWebTokenService.encode({ user_id: user.id }, nil) # nil expiration for never expiring

      render json: {
        pub_id: user.public_id,
        beta_access: beta_access,
        jwt: token
      }, status: :ok
    rescue => e
      Rails.logger.error("Error in onboarding user: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: "Failed to onboard user" }, status: :internal_server_error
    end

    def flag_is_enabled
      feature_name = params[:flag_name]
      if feature_name.blank?
        render json: { error: "flag_name is required" }, status: :bad_request
        return
      end

      feature_sym = feature_name.to_sym
      unless FlipperFlags::ALL_FLAGS.include?(feature_sym)
        render json: { error: "Unknown feature flag", feature_name: feature_name }, status: :not_found
        return
      end

      flipper_key = FlipperFlags::MAP[feature_sym]
      if flipper_key.nil?
        render json: { error: "Invalid flag mapping", feature_name: feature_name }, status: :unprocessable_content
        return
      end

      feature = Flipper[flipper_key] # Flipper::Feature
      is_enabled = feature.enabled?(current_user)

      render json: { feature_name: feature_name, is_enabled: is_enabled }, status: :ok
    end


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

    def get_email
      authorize current_user, :show?

      email = Email.where(user_id: current_user.id, primary: true).pick(:email)

      render json: { email: email }, status: :ok
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
      authorize email_record, email_record.new_record? ? :create? : :update?
      email_record.g_cal = true
      email_record.save!

      # Check if user has completed OAuth for at least one email
      if current_user.google_credential.nil?
        render json: {
          error: "You must complete Google OAuth for at least one email before adding calendar access. Please use the /api/user/gcal endpoint first."
        }, status: :unprocessable_content
        return
      end

      # trigger function to ensure calendar is shared with that email synchronously
      service = GoogleCalendarService.new(current_user)
      calendar_id = service.create_or_get_course_calendar
      service.share_calendar_with_email(calendar_id, email)

      # Note: Sharing the calendar doesn't require a full sync
      # Events are already created. The new email just gets access to the existing calendar.

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

      authorize email_record, :destroy?

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
      authorize email_record, email_record.new_record? ? :create? : :update?
      email_record.g_cal = true
      email_record.save!

      # Check if this email already has OAuth credentials
      if current_user.google_credential_for_email(email).present?
        # Email has credentials, ensure calendar is created and shared
        service = GoogleCalendarService.new(current_user)
        calendar_id = service.create_or_get_course_calendar

        # Note: Don't sync here - may run before enrollments exist!
        # The sync will be triggered by CourseProcessorService after enrollments are created.
        # For existing users with enrollments, they can manually trigger a sync.

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

    def group_meeting_times(meeting_times)
      # Create preference resolver for the user
      preference_resolver = PreferenceResolver.new(current_user)
      template_renderer = CalendarTemplateRenderer.new

      # Return each meeting time individually with its own ID
      # This ensures each day can be edited independently in the extension
      meeting_times.map do |mt|
        # Initialize days object with only this meeting time's day set to true
        days = {
          monday: false,
          tuesday: false,
          wednesday: false,
          thursday: false,
          friday: false,
          saturday: false,
          sunday: false
        }

        # Set only the current meeting time's day to true
        day_symbol = mt.day_of_week&.to_sym
        days[day_symbol] = true if day_symbol

        # Resolve preferences for this meeting time (ignore DND for display purposes)
        preferences = preference_resolver.resolve_actual_for(mt)

        # Build template context
        context = CalendarTemplateRenderer.build_context_from_meeting_time(mt)

        # Render title and description from templates
        rendered_title = if preferences[:title_template].present?
                           template_renderer.render(preferences[:title_template], context)
                         else
                           titleize_with_roman_numerals(mt.course.title)
                         end

        rendered_description = if preferences[:description_template].present?
                                 template_renderer.render(preferences[:description_template], context)
                               else
                                 nil
                               end

        # Convert color to WITCC hex format
        # Use preference color if set, otherwise use meeting time's default color
        color_value = preferences[:color_id] || mt.event_color
        witcc_color = GoogleColors.to_witcc_hex(color_value)

        {
          id: mt.public_id,
          begin_time: mt.fmt_begin_time_military,
          end_time: mt.fmt_end_time_military,
          start_date: mt.start_date,
          end_date: mt.end_date,
          location: {
            building: if mt.building
                        {
                          pub_id: mt.building.public_id,
                          name: mt.building.name,
                          abbreviation: mt.building.abbreviation
                        }
                      else
                        nil
                      end,
            room: mt.room&.formatted_number
          },
          **days,
          # Preference-resolved calendar configuration
          calendar_config: {
            title: rendered_title,
            description: rendered_description,
            color_id: witcc_color,
            reminder_settings: preferences[:reminder_settings],
            visibility: preferences[:visibility]
          }
        }
      end
    end

    def get_ics_url
      authorize current_user, :show?

      render json: {
        ics_url: current_user.cal_url_with_extension
      }
    end

    def list_oauth_credentials
      authorize current_user, :show?

      credentials = current_user.oauth_credentials.includes(:google_calendar).map do |credential|
        {
          id: credential.public_id,
          email: credential.email,
          provider: credential.provider,
          has_calendar: credential.google_calendar.present?,
          calendar_id: credential.google_calendar&.google_calendar_id,
          created_at: credential.created_at,
          needs_reauth: credential.needs_reauth?,
          token_revoked: credential.token_revoked?
        }
      end

      render json: { oauth_credentials: credentials }, status: :ok
    end

    def disconnect_oauth_credential
      credential_id = params[:credential_id]

      if credential_id.blank?
        render json: { error: "credential_id is required" }, status: :bad_request
        return
      end

      # Accept both internal ID and public_id
      credential = find_by_any_id(OauthCredential, credential_id)
      credential = nil unless credential&.user_id == current_user.id

      if credential.nil?
        render json: { error: "OAuth credential not found" }, status: :not_found
        return
      end

      authorize credential, :destroy?

      # Check if this is the last credential
      if current_user.oauth_credentials.one?
        render json: {
          error: "Cannot disconnect the last OAuth credential. You must have at least one connected account."
        }, status: :unprocessable_content
        return
      end

      credential.destroy!

      render json: { message: "OAuth credential disconnected successfully" }, status: :ok
    rescue => e
      Rails.logger.error("Error disconnecting OAuth credential for user #{current_user.id}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: "Failed to disconnect OAuth credential" }, status: :internal_server_error
    end

    # GET /api/user/notifications_status
    # Returns the current notifications DND status
    def notifications_status
      authorize current_user, :show?

      render json: {
        notifications_disabled: current_user.notifications_disabled?,
        notifications_disabled_until: current_user.notifications_disabled_until
      }, status: :ok
    end

    # POST /api/user/notifications/disable
    # Disables all notifications (DND mode)
    # Optional params:
    #   - duration: duration in seconds (nil for indefinite)
    def disable_notifications
      authorize current_user, :update?

      # Check if duration param was provided (using params.key? for explicit presence check)
      duration_provided = params.key?(:duration) && params[:duration].present?
      duration_seconds = params[:duration].to_i if duration_provided

      # Validate duration if provided
      if duration_provided
        if duration_seconds < 0
          render json: { error: "Duration cannot be negative" }, status: :bad_request
          return
        end

        # Cap at 100 years to prevent abuse/overflow issues
        max_duration = 100.years.to_i
        if duration_seconds > max_duration
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
        message: "Notifications disabled",
        notifications_disabled: true,
        notifications_disabled_until: current_user.notifications_disabled_until
      }, status: :ok
    rescue => e
      Rails.logger.error("Error disabling notifications for user #{current_user.id}: #{e.message}")
      render json: { error: "Failed to disable notifications" }, status: :internal_server_error
    end

    # POST /api/user/notifications/enable
    # Re-enables notifications (turns off DND mode)
    def enable_notifications
      authorize current_user, :update?

      current_user.enable_notifications!

      # Trigger calendar sync to restore reminders
      # The sync job will gracefully handle cases where user has no Google Calendar
      current_user.update_column(:calendar_needs_sync, true) # rubocop:disable Rails/SkipsModelValidations
      GoogleCalendarSyncJob.perform_later(current_user, force: true)


      render json: {
        message: "Notifications enabled",
        notifications_disabled: false,
        notifications_disabled_until: nil
      }, status: :ok
    rescue => e
      Rails.logger.error("Error enabling notifications for user #{current_user.id}: #{e.message}")
      render json: { error: "Failed to enable notifications" }, status: :internal_server_error
    end

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

      # Preload user's calendar preferences to avoid N+1 queries in PreferenceResolver
      current_user.calendar_preferences.load
      current_user.event_preferences.load

      # Preload course associations to prevent N+1 (meeting_times, faculties, buildings, rooms, event_preferences)
      enrollments = current_user
                    .enrollments
                    .where(term_id: term.id)
                    .includes(course: [
                                :faculties,
                                { meeting_times: [:event_preference, { room: :building }, { course: :faculties }] }
                              ])

      structured_data = enrollments.map do |enrollment|
        course = enrollment.course
        faculty = course.faculties.first # safer than [0]

        # Filter meeting times to prefer valid locations over TBD duplicates
        filtered_meeting_times = course.meeting_times.group_by { |mt| [mt.day_of_week, mt.begin_time, mt.end_time] }
                                       .map do |key, meeting_times_group|
                                         # Log duplicate detection
                                         if meeting_times_group.size > 1
                                           Rails.logger.info "[API] Duplicate meeting times detected for course #{course.crn}: #{meeting_times_group.size} entries for #{key.inspect}"
                                         end

                                         # If multiple meeting times exist for same day/time, prefer non-TBD over TBD
                                         non_tbd = meeting_times_group.reject { |mt| (mt.building && current_user.send(:tbd_building?, mt.building)) || (mt.room && current_user.send(:tbd_room?, mt.room)) }
                                         # Take only the first valid one, or first TBD if no valid ones
                                         selected = non_tbd.any? ? non_tbd.first : meeting_times_group.first

                                         if meeting_times_group.size > 1
                                           Rails.logger.info "[API] Selected meeting time #{selected.id} with location: #{selected.building&.name} - #{selected.room&.number}"
                                         end

                                         selected
        end

        {
          title: titleize_with_roman_numerals(course.title),
          course_number: course.course_number,
          schedule_type: course.schedule_type,
          prefix: course.prefix,
          term: {
            pub_id: term.public_id,
            uid: term.uid,
            season: term.season,
            year: term.year
          },
          professor: if faculty
                       {
                         pub_id: faculty.public_id,
                         first_name: faculty.first_name,
                         last_name: faculty.last_name,
                         email: faculty.email,
                         rmp_id: faculty.rmp_id
                       }
                     else
                       nil
                     end,
          # Note: We pass filtered_meeting_times (not grouped) to ensure each day has unique ID
          meeting_times: group_meeting_times(filtered_meeting_times)
        }
      end

      render json: {
        classes: structured_data,
        notifications_disabled: current_user.notifications_disabled?
      }, status: :ok
    end



  end
end
