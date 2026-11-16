# frozen_string_literal: true

module GoogleCalendar
  # The Google remote calls of CourseCalendars::Provider, which runs the sync.
  #
  #   GoogleCalendar::CalendarManager   create, share, list, and delete the calendar
  #   GoogleCalendar::EventPayload      the Google::Apis::CalendarV3::Event for an event hash, and back
  #   GoogleCalendar::EventLabels       the event label of each custom color
  #   GoogleCalendar::CalendarServices  authorized Google API services
  #
  # Every call goes through the rate limiter, so the settings in
  # config/initializers/google_api_rate_limiting.rb apply.
  class Provider < CourseCalendars::Provider
    include GoogleCalendar::RateLimiter

    # A missing event: Google answers 404 for an event it never had, and 410
    # Gone for an event that was already deleted.
    GONE_STATUSES = [ 404, 410 ].freeze

    # Signet::AuthorizationError is a refused refresh token, which
    # Google::Auth::AuthorizationError subclasses.
    AUTH_ERRORS = [ Google::Apis::AuthorizationError, Signet::AuthorizationError ].freeze
    # The google-apis gem raises RateLimitError for a 429 and for a 403 with
    # the reason rateLimitExceeded, userRateLimitExceeded or
    # sharingRateLimitExceeded.
    RATE_LIMIT_ERRORS = [ Google::Apis::RateLimitError ].freeze
    TRANSIENT_ERRORS  = [ *RATE_LIMIT_ERRORS, Google::Apis::ServerError ].freeze

    # A second Google account only shares the calendar, so the person's edits
    # stay.
    FORCE_SYNC_ON_RECONNECT = false

    # OmniAuth serves this path, so it has no route.
    CONNECT_PATH = "/auth/google_oauth2"

    def self.gone?(error)
      error.is_a?(Google::Apis::ClientError) && GONE_STATUSES.include?(error.status_code)
    end

    # A linked Google account without a course calendar has nothing to sync.
    def self.syncs_for?(user)
      CourseCalendar.google.for_user(user).exists?
    end

    # With an email, the callback accepts only that account.
    def self.connect_path(user, email: nil)
      "#{CONNECT_PATH}?#{{ state: GoogleSignIn::OauthState.generate(user_id: user.id, email: email) }.to_query}"
    end

    def self.delete_event_later(ref)
      GoogleCalendar::EventDeleteJob.perform_later(ref[:calendar_id], ref[:event_id])
    end

    def self.delete_calendar_later(calendar)
      GoogleCalendar::DeleteJob.perform_later(calendar.external_calendar_id)
    end

    def self.refreshable?
      true
    end

    def self.refresh_token!(credential)
      GoogleCalendar::CalendarServices.authorization(credential, refresh: true)
    end

    def self.invalid_grant?(error)
      error.is_a?(Signet::AuthorizationError) && error.message.match?(/"error"\s*:\s*"invalid_grant"/)
    end

    # The course calendar belongs to one credential, but it is shared with every
    # Google account the person connects. So look it up for the user, not only
    # on this credential. Uses the account's own token, so it runs before the
    # token is revoked. Google can refuse or be down, and that must not block
    # the disconnect.
    def self.release_calendar(credential)
      calendar_id = CourseCalendar.google.for_user(credential.user).pick(:external_calendar_id) if credential.user
      return if calendar_id.blank?

      manager = GoogleCalendar::CalendarManager.new(credential.user)
      report_disconnect_failure(credential, "remove the course calendar from the calendar list") do
        manager.remove_from_calendar_list(calendar_id, credential.email)
      end
      report_disconnect_failure(credential, "stop sharing the course calendar") do
        manager.unshare_with_email(calendar_id, credential.email)
      end
    end

    # The refresh token ends the whole grant. Google does not revoke an access
    # token that has expired.
    def self.revoke_later(credential)
      GoogleSignIn::RevokeTokenJob.perform_later(
        GoogleSignIn::RevokeTokenJob.seal(credential.refresh_token.presence || credential.access_token)
      )
    end

    def self.report_disconnect_failure(credential, action)
      yield
    rescue Google::Apis::Error, Signet::AuthorizationError, Signet::RemoteServerError,
           Signet::UnexpectedStatusError, Faraday::Error => e
      Rails.error.report(e, handled: true, context: { oauth_credential_id: credential.id, action: action })
    end
    private_class_method :report_disconnect_failure

    def course_calendar
      CourseCalendar.google.for_user(user).first
    end

    def create_or_get_course_calendar(**)
      calendar = course_calendar

      if calendar.blank?
        google_api_calendar = calendar_manager.create_calendar
        credential = user.google_credential
        raise "No Google OAuth credentials found for user" unless credential

        calendar = credential.create_course_calendar!(
          external_calendar_id: google_api_calendar.id,
          summary:              google_api_calendar.summary,
          description:          google_api_calendar.description,
          time_zone:            google_api_calendar.time_zone
        )
      end

      calendar_manager.share_with_user(calendar.external_calendar_id)
      calendar_manager.add_to_all_calendar_lists(calendar.external_calendar_id)

      calendar.external_calendar_id
    end

    # The emails, in lower case, of the attendees who declined the invitation
    # to a meeting event. A tentative answer is not a decline. A missing event
    # has none.
    def declined_attendee_emails(row)
      event = with_rate_limit_handling { user_calendar_service.get_event(calendar_id_of(row), row.external_event_id) }

      Array(event.attendees).select { |attendee| attendee.response_status == "declined" }
                            .map { |attendee| attendee.email.to_s.downcase }
    rescue Google::Apis::ClientError => e
      raise unless self.class.gone?(e)

      []
    end

    private

    def calendar_manager
      @calendar_manager ||= GoogleCalendar::CalendarManager.new(user)
    end

    def user_calendar_service
      @user_calendar_service ||= GoogleCalendar::CalendarServices.for_user(user)
    end

    def connect!
      user_calendar_service
    end

    def rate_limited?(error)
      RATE_LIMIT_ERRORS.any? { |klass| error.is_a?(klass) }
    end

    def each_paced(rows, &)
      with_batch_throttling(rows, &)
    end

    def calendar_id_of(row)
      row.course_calendar.external_calendar_id
    end

    def labels_for(calendar)
      @labels ||= {}
      @labels[calendar.external_calendar_id] ||= GoogleCalendar::EventLabels.new(user_calendar_service, calendar.external_calendar_id)
    end

    def insert_event(calendar, data)
      google_event = EventPayload.build(data, labels_for(calendar))
      created = with_rate_limit_handling do
        user_calendar_service.insert_event(calendar.external_calendar_id, google_event, **EventPayload.request_options(google_event))
      end
      { external_event_id: created.id }
    end

    def fetch_event(row)
      google_event = with_rate_limit_handling { user_calendar_service.get_event(calendar_id_of(row), row.external_event_id) }
      EventPayload.remote_event(row, google_event)
    rescue Google::Apis::ClientError => e
      raise unless self.class.gone?(e)
    end

    def patch_event(row, event_id, data, remote:, force:) # rubocop:disable Lint/UnusedMethodArgument
      google_event = EventPayload.build(data, labels_for(row.course_calendar))
      with_rate_limit_handling do
        user_calendar_service.update_event(calendar_id_of(row), event_id, google_event, **EventPayload.request_options(google_event))
      end
      event_id
    rescue Google::Apis::ClientError => e
      raise unless self.class.gone?(e)
    end

    def delete_event(row)
      with_rate_limit_handling { user_calendar_service.delete_event(calendar_id_of(row), row.external_event_id) }
    rescue Google::Apis::ClientError => e
      raise unless self.class.gone?(e)

      Rails.logger.warn({ message: "Event not found in Google Calendar, removing the row", user_id: user.id,
                          external_event_id: row.external_event_id }.to_json)
    end

    def delete_duplicate_event(calendar, event_id)
      with_rate_limit_handling { user_calendar_service.delete_event(calendar.external_calendar_id, event_id, send_updates: "none") }
    end

    def insert_friend_meeting(calendar, meeting, invite:)
      google_event = EventPayload.for_friend_meeting(meeting, attendees: invite)
      send_updates = google_event.attendees.present? ? "all" : "none"
      created = with_rate_limit_handling do
        user_calendar_service.insert_event(calendar.external_calendar_id, google_event, send_updates: send_updates)
      end
      { external_event_id: created.id }
    end

    def patch_friend_meeting(row, meeting, attendees:)
      google_event = EventPayload.for_friend_meeting(meeting, attendees: attendees)
      with_rate_limit_handling do
        user_calendar_service.update_event(calendar_id_of(row), row.external_event_id, google_event,
                                           send_updates: attendees ? "all" : "none")
      end
      row.external_event_id
    rescue Google::Apis::ClientError => e
      raise unless self.class.gone?(e)
    end

    def delete_friend_meeting(row)
      with_rate_limit_handling { user_calendar_service.delete_event(calendar_id_of(row), row.external_event_id, send_updates: "all") }
    rescue Google::Apis::ClientError => e
      raise unless self.class.gone?(e)
    end
  end
end
