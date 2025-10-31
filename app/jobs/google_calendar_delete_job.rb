class GoogleCalendarDeleteJob < ApplicationJob
  queue_as :default

  def perform(calendar_id)
    GoogleCalendarService.new.delete_calendar(calendar_id)
  end
end
