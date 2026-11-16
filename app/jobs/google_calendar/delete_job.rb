# frozen_string_literal: true

module GoogleCalendar
  # Deletes a course calendar with the service account. Enqueued when a Google
  # CourseCalendar row is destroyed. A calendar that is gone counts as deleted.
  class DeleteJob < ApplicationJob
    include CourseCalendars::ProviderRetries

    queue_as :high

    retry_on_rate_limits

    def perform(calendar_id)
      GoogleCalendar::CalendarManager.new.delete_calendar(calendar_id)
    rescue Google::Apis::ClientError => e
      raise unless GoogleCalendar::Provider.gone?(e)

      Rails.logger.info("Calendar #{calendar_id} already deleted")
    end
  end
end
