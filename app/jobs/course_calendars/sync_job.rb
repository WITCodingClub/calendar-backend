# frozen_string_literal: true

module CourseCalendars
  class SyncJob < ApplicationJob
    queue_as :high

    # The concurrency group is part of every lock key, so it must not change when
    # the class is renamed. Jobs in the queue hold locks under this name.
    CONCURRENCY_GROUP = "GoogleCalendarSyncJob"

    # A full sync of a large schedule can take many minutes. The lock must
    # last longer than the job, or a second sync for the user starts and both
    # create the same remote events.
    limits_concurrency to: 1, group: CONCURRENCY_GROUP, key: ->(user, **) { "google_calendar_sync_user_#{user.id}" },
                       duration: 1.hour

    def perform(user, force: false, backfill_historical: force, nightly: false)
      user.sync_course_schedule(force: force, backfill_historical: backfill_historical)

      # CourseCalendars::NightlySyncJob picks users by these columns. Record
      # every nightly sync, also one that changed nothing, so the user is not
      # picked again in each run.
      user.update!(calendar_needs_sync: false, last_calendar_sync_at: Time.current) if nightly
    end
  end
end
