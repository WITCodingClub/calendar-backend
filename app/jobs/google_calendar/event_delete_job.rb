# frozen_string_literal: true

module GoogleCalendar
  # Deletes one event from a Google Calendar. Enqueued when a CalendarEvent row
  # is destroyed, for example when its meeting time was removed, so the live
  # Google event does not stay behind.
  class EventDeleteJob < ApplicationJob
    include CourseCalendars::ProviderRetries

    queue_as :high

    retry_on_rate_limits

    def perform(calendar_id, external_event_id)
      return if calendar_id.blank? || external_event_id.blank?

      GoogleCalendar::CalendarManager.new.delete_event(calendar_id, external_event_id)
    end
  end
end
