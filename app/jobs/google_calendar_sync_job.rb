class GoogleCalendarSyncJob < ApplicationJob
  queue_as :default

  def perform(user)
    user.sync_course_schedule
  end
end
