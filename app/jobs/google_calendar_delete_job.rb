class GoogleCalendarDeleteJob < ApplicationJob
  queue_as :high_priority

  def perform(calendar_id)
    GoogleCalendarService.new.delete_calendar(calendar_id)
  end
end
