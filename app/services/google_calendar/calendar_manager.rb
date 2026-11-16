# frozen_string_literal: true

module GoogleCalendar
  # Calendar-level calls: create and delete the course calendar, share it with
  # each linked Google account through an ACL rule, and add it to (or remove it
  # from) each account's calendar list.
  #
  # The service account owns the calendar. A calendar list belongs to one
  # account, so those calls use that account's own token. Every call goes
  # through the rate limiter, so the retry settings in
  # config/initializers/google_api_rate_limiting.rb apply.
  class CalendarManager
    include GoogleCalendar::RateLimiter

    CALENDAR_COLOR_ID = "7"

    # Google answers 404 while a new calendar has not reached the account yet.
    class NotListableYetError < StandardError; end

    # user is the person whose calendar is shared or listed. The calls that
    # only use the service account work without one.
    def initialize(user = nil)
      @user = user
    end

    # Creates the course calendar with the service account. Returns the
    # Google::Apis::CalendarV3::Calendar.
    def create_calendar
      service = CalendarServices.service_account

      calendar = Google::Apis::CalendarV3::Calendar.new(
        summary:     CourseCalendars::Provider.calendar_name,
        description: "#{CourseCalendars::Provider.env_prefix}Course schedule for #{user.email}.\nCreated and Updated by WIT Course Calendar App.",
        time_zone:   SchoolTimeZone::NAME
      )

      with_rate_limit_handling { service.insert_calendar(calendar) }
    end

    # Shares the calendar with all of the user's Google-authenticated emails via ACL.
    def share_with_user(calendar_id)
      service = CalendarServices.service_account

      with_batch_throttling(user.google_credentials.to_a) do |credential|
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
      with_rate_limit_handling { service.delete_acl(calendar_id, "user:#{email}") }
    rescue Google::Apis::ClientError => e
      raise unless GoogleCalendar::Provider.gone?(e)

      Rails.logger.info("ACL rule for #{email} already absent from calendar #{calendar_id}")
    end

    # An account that cannot see the new calendar yet gets it from
    # GoogleCalendar::CalendarListJob, so no request or job waits here.
    def add_to_all_calendar_lists(calendar_id)
      with_batch_throttling(user.google_credentials.to_a) do |credential|
        add_to_calendar_list(calendar_id, credential.email)
      rescue NotListableYetError
        CalendarListJob.set(wait: CalendarListJob::WAIT).perform_later(user, calendar_id, credential.email)
      end
    end

    # A calendar that is already in the list is done. Raises
    # NotListableYetError while the account cannot see the calendar.
    def add_to_calendar_list(calendar_id, email)
      credential = user.google_credential_for_email(email)
      return unless credential

      service = CalendarServices.for_credential(credential)

      calendar_list_entry = Google::Apis::CalendarV3::CalendarListEntry.new(
        id:               calendar_id,
        summary_override: CourseCalendars::Provider::CALENDAR_NAME,
        color_id:         CALENDAR_COLOR_ID,
        selected:         true,
        hidden:           false
      )

      with_rate_limit_handling { service.insert_calendar_list(calendar_list_entry) }
    rescue Google::Apis::ClientError => e
      case e.status_code
      when 409 then Rails.logger.debug { "Calendar #{calendar_id} already in list for #{email}" }
      when 404 then raise NotListableYetError, "Calendar #{calendar_id} is not visible to the account yet"
      else raise
      end
    end

    # Uses that account's own token, so call it before the token is revoked.
    def remove_from_calendar_list(calendar_id, email)
      course_calendar = CourseCalendar.google.find_by(external_calendar_id: calendar_id)
      return unless course_calendar

      credential = course_calendar.user.google_credential_for_email(email)
      return unless credential

      service = CalendarServices.for_credential(credential)
      with_rate_limit_handling { service.delete_calendar_list(calendar_id) }
    rescue Google::Apis::ClientError => e
      Rails.logger.warn "Failed to remove calendar from user list: #{e.message}" unless GoogleCalendar::Provider.gone?(e)
    end

    # Removes the calendar from the list of each account that owns it, then
    # deletes the calendar with the service account.
    def delete_calendar(calendar_id)
      course_calendar = CourseCalendar.google.find_by(external_calendar_id: calendar_id)

      if course_calendar
        with_batch_throttling(course_calendar.user.google_credentials.to_a) do |credential|
          remove_from_calendar_list(calendar_id, credential.email)
        end
      end

      service = CalendarServices.service_account
      with_rate_limit_handling { service.delete_calendar(calendar_id) }
    end

    def list_calendars
      service = CalendarServices.service_account
      with_rate_limit_handling { service.list_calendar_lists }
    end

    # Deletes one event with the service account, which owns every calendar
    # the app makes, so it works whatever the state of the person's token. A
    # missing event counts as deleted.
    def delete_event(calendar_id, event_id)
      service = CalendarServices.service_account
      with_rate_limit_handling { service.delete_event(calendar_id, event_id) }
    rescue Google::Apis::ClientError => e
      raise unless GoogleCalendar::Provider.gone?(e)

      Rails.logger.info("Event #{event_id} already absent from calendar #{calendar_id}")
    end

    private

    attr_reader :user
  end
end
