# frozen_string_literal: true

class GoogleCalendarSyncJob < ApplicationJob
  queue_as :high

  limits_concurrency to: 1, key: ->(user, force: false) { "google_calendar_sync_user_#{user.id}" }

  def perform(user, force: false)
    user.sync_course_schedule(force: force)
  end
end
