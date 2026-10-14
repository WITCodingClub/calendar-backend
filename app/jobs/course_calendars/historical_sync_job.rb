# frozen_string_literal: true

module CourseCalendars
  class HistoricalSyncJob < ApplicationJob
    queue_as :low

    # The concurrency group is part of every lock key, so it must not change when
    # the class is renamed. Jobs in the queue hold locks under this name.
    CONCURRENCY_GROUP = "GoogleCalendarHistoricalSyncJob"

    # Past finals and university events for every term can take many minutes,
    # so the lock lasts longer than the 3-minute default.
    limits_concurrency to: 1, group: CONCURRENCY_GROUP, key: ->(user, force: false) { "google_calendar_historical_user_#{user.id}" },
                       duration: 1.hour

    def perform(user, force: false)
      user.sync_historical_events(force: force)
    end
  end
end
