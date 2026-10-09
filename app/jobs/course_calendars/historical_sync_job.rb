# frozen_string_literal: true

module CourseCalendars
  class HistoricalSyncJob < ApplicationJob
    queue_as :low

    # The concurrency group is part of every lock key, so it must not change when
    # the class is renamed. Jobs in the queue hold locks under this name.
    CONCURRENCY_GROUP = "GoogleCalendarHistoricalSyncJob"

    limits_concurrency to: 1, group: CONCURRENCY_GROUP, key: ->(user, force: false) { "google_calendar_historical_user_#{user.id}" }

    def perform(user, force: false)
      user.sync_historical_events(force: force)
    end
  end
end
