# frozen_string_literal: true

class GoogleCalendarSyncJob < ApplicationJob
  queue_as :high

  # The concurrency group is part of every lock key, so it must not change when
  # the class is renamed. Jobs in the queue hold locks under this name.
  CONCURRENCY_GROUP = "GoogleCalendarSyncJob"

  limits_concurrency to: 1, group: CONCURRENCY_GROUP, key: ->(user, force: false) { "google_calendar_sync_user_#{user.id}" }

  def perform(user, force: false)
    user.sync_course_schedule(force: force)
  end
end
