# frozen_string_literal: true

class GoogleCalendarSyncJob < ApplicationJob
  queue_as :high

  # Use concurrency keys to prevent multiple sync jobs for the same user
  # Only one job with the same concurrency key will run at a time
  limits_concurrency to: 1, key: ->(user, force: false) { "google_calendar_sync_user_#{user.id}" }

  def perform(user, force: false)
    user.sync_course_schedule(force: force)
  end

end
