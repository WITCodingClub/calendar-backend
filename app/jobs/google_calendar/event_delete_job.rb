# frozen_string_literal: true

module GoogleCalendar
  # Deletes a single event from a Google Calendar. Enqueued when a
  # CalendarEvent DB row is destroyed (e.g. its meeting time was removed
  # during reconcile) so the live Google event is removed too, rather than left
  # behind as an untracked orphan.
  class EventDeleteJob < ApplicationJob
    queue_as :high

    def perform(calendar_id, external_event_id)
      return if calendar_id.blank? || external_event_id.blank?

      GoogleCalendar::Provider.new.delete_calendar_event(calendar_id, external_event_id)
    end
  end
end
