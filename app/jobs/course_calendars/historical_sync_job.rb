# frozen_string_literal: true

module CourseCalendars
  class HistoricalSyncJob < ApplicationJob
    include CourseCalendars::ProviderRetries

    queue_as :low

    # The concurrency group is part of every lock key, so it must not change when
    # the class is renamed. Jobs in the queue hold locks under this name.
    CONCURRENCY_GROUP = "GoogleCalendarHistoricalSyncJob"

    # Its own lock, not CourseCalendars::UserLock: a backfill of every past
    # term can take many minutes, and the person's own syncs must not wait for
    # it. It only makes and updates past events, and a race with a sync ends
    # in the unique row index (CourseCalendars::Provider#create_event). It
    # holds the lock as long as UserLock does, because it can run as long.
    limits_concurrency to: 1, group: CONCURRENCY_GROUP, key: ->(user, **) { "google_calendar_historical_user_#{user.id}" },
                       duration: CourseCalendars::UserLock::DURATION

    retry_on_rate_limits

    def perform(user, force: false)
      CourseCalendars::ScheduleSyncer.new(user).sync_historical(force: force)
    end
  end
end
