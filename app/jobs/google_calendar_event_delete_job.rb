# frozen_string_literal: true

# Deletes a single event from a Google Calendar. Enqueued when a
# GoogleCalendarEvent DB row is destroyed (e.g. its meeting time was removed
# during reconcile) so the live Google event is removed too, rather than left
# behind as an untracked orphan.
class GoogleCalendarEventDeleteJob < ApplicationJob
  queue_as :high

  def perform(calendar_id, google_event_id)
    return if calendar_id.blank? || google_event_id.blank?

    GoogleCalendarService.new.delete_calendar_event(calendar_id, google_event_id)
  end
end
