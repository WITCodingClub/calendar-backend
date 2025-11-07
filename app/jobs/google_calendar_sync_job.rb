# frozen_string_literal: true

class GoogleCalendarSyncJob < ApplicationJob
  queue_as :high

  def perform(user, force: false)
    user.sync_course_schedule(force: force)
  end

end
