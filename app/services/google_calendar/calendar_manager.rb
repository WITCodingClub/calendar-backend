# frozen_string_literal: true

module GoogleCalendar
  # Calendar-level calls: create and delete the course calendar, share it with
  # each linked Google account through an ACL rule, and add it to (or remove it
  # from) each account's calendar list.
  #
  # The service account owns the calendar. A calendar list belongs to one
  # account, so those calls use that account's own token. Every call goes
  # through the rate limiter it is given (GoogleCalendar::Provider), so the
  # retry settings in config/initializers/google_api_rate_limiting.rb apply.
  class CalendarManager
    CALENDAR_NAME      = "WIT Courses"
    CALENDAR_COLOR_ID  = "7"
    TIME_ZONE          = "America/New_York"
    ENV_PREFIXES       = { "test" => "[TEST] ", "development" => "[DEV] ", "stage" => "[STAGE] " }.freeze
    LIST_RETRIES       = 3
    LIST_RETRY_SECONDS = 10

    def initialize(user, rate_limiter:)
      @user         = user
      @rate_limiter = rate_limiter
    end

    # Creates the course calendar with the service account. Returns the
    # Google::Apis::CalendarV3::Calendar.
    def create_calendar
      service    = CalendarServices.service_account
      env_prefix = ENV_PREFIXES[Rails.env] || ""

      calendar = Google::Apis::CalendarV3::Calendar.new(
        summary:     "#{env_prefix}#{CALENDAR_NAME}",
        description: "#{env_prefix}Course schedule for #{user.email}.\nCreated and Updated by WIT Course Calendar App.",
        time_zone:   TIME_ZONE
      )

      rate_limiter.with_rate_limit_handling { service.insert_calendar(calendar) }
    end

    # Shares the calendar with all of the user's Google-authenticated emails via ACL.
    def share_with_user(calendar_id)
      service = CalendarServices.service_account

      rate_limiter.with_batch_throttling(user.google_credentials.to_a) do |credential|
        rule = Google::Apis::CalendarV3::AclRule.new(
          scope: { type: "user", value: credential.email },
          role:  "owner"
        )

        begin
          service.insert_acl(calendar_id, rule, send_notifications: false)
        rescue Google::Apis::ClientError => e
          raise unless e.status_code == 409
        end
      end
    end

    # Deletes the ACL rule that share_with_user added for the email. Without
    # this, a disconnected account keeps owner access to the calendar. Uses the
    # service account, so it works after the account's token is gone.
    def unshare_with_email(calendar_id, email)
      service = CalendarServices.service_account
      rate_limiter.with_rate_limit_handling { service.delete_acl(calendar_id, "user:#{email}") }
    rescue Google::Apis::ClientError => e
      raise unless e.status_code == 404

      Rails.logger.info("ACL rule for #{email} already absent from calendar #{calendar_id}")
    end

    def add_to_all_calendar_lists(calendar_id)
      rate_limiter.with_batch_throttling(user.google_credentials.to_a) do |credential|
        add_to_calendar_list(calendar_id, credential.email)
      end
    end

    # A new calendar can take some seconds to reach the account, so a 404 is
    # tried again after a wait. A calendar that is already in the list is done.
    def add_to_calendar_list(calendar_id, email)
      credential = user.google_credential_for_email(email)
      return unless credential

      service = CalendarServices.for_credential(credential)

      calendar_list_entry = Google::Apis::CalendarV3::CalendarListEntry.new(
        id:               calendar_id,
        summary_override: CALENDAR_NAME,
        color_id:         CALENDAR_COLOR_ID,
        selected:         true,
        hidden:           false
      )

      retries = 0

      begin
        rate_limiter.with_rate_limit_handling { service.insert_calendar_list(calendar_list_entry) }
      rescue Google::Apis::ClientError => e
        if e.status_code == 409
          Rails.logger.debug { "Calendar #{calendar_id} already in list for #{email}" }
        elsif e.status_code == 404 && retries < LIST_RETRIES
          retries += 1
          wait_time = LIST_RETRY_SECONDS * retries
          Rails.logger.warn "Calendar #{calendar_id} not accessible yet for #{email} - retrying in #{wait_time}s (attempt #{retries}/#{LIST_RETRIES})"
          sleep(wait_time)
          retry
        elsif e.status_code == 404
          Rails.logger.error "Calendar #{calendar_id} still not accessible for #{email} after #{LIST_RETRIES} retries"
          raise
        else
          raise
        end
      end
    end

    # Uses that account's own token, so call it before the token is revoked.
    def remove_from_calendar_list(calendar_id, email)
      course_calendar = CourseCalendar.google.find_by(external_calendar_id: calendar_id)
      return unless course_calendar

      credential = course_calendar.user.google_credential_for_email(email)
      return unless credential

      service = CalendarServices.for_credential(credential)
      rate_limiter.with_rate_limit_handling { service.delete_calendar_list(calendar_id) }
    rescue Google::Apis::ClientError => e
      Rails.logger.warn "Failed to remove calendar from user list: #{e.message}" unless e.status_code == 404
    end

    # Removes the calendar from the list of each account that owns it, then
    # deletes the calendar with the service account.
    def delete_calendar(calendar_id)
      course_calendar = CourseCalendar.google.find_by(external_calendar_id: calendar_id)

      if course_calendar
        rate_limiter.with_batch_throttling(course_calendar.user.google_credentials.to_a) do |credential|
          remove_from_calendar_list(calendar_id, credential.email)
        end
      end

      service = CalendarServices.service_account
      rate_limiter.with_rate_limit_handling { service.delete_calendar(calendar_id) }
    end

    def list_calendars
      service = CalendarServices.service_account
      rate_limiter.with_rate_limit_handling { service.list_calendar_lists }
    end

    private

    attr_reader :user, :rate_limiter
  end
end
