# frozen_string_literal: true

module GoogleCalendar
  # Adds a new course calendar to the calendar list of one Google account. A
  # new calendar can take some seconds to reach the account, so the job runs
  # 10 seconds after the first try (GoogleCalendar::CalendarManager
  # #add_to_all_calendar_lists), then 20 and 30 seconds later, and then gives up.
  class CalendarListJob < ApplicationJob
    include CourseCalendars::ProviderRetries

    WAIT     = 10.seconds
    ATTEMPTS = 3

    queue_as :high

    retry_on_provider_errors
    retry_on CalendarManager::NotListableYetError, wait: ->(executions) { WAIT * (executions + 1) }, attempts: ATTEMPTS
    discard_on_auth_errors

    def perform(user, calendar_id, email)
      CalendarManager.new(user).add_to_calendar_list(calendar_id, email)
    end
  end
end
