class GoogleCalendarSyncJob < ApplicationJob
  queue_as :high_priority

  def perform(user)
    user.sync_course_schedule
  end
end
