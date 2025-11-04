class GoogleCalendarSyncJob < ApplicationJob
  queue_as :high

  def perform(user)
    user.sync_course_schedule
  end
end
