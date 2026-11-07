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

    retry_on Google::Apis::RateLimitError, **GoogleCalendar::RateLimiter::JOB_RETRY

    # Solid Queue runs the job with the lowest number first. Other jobs use 0.
    BULK_PRIORITY = 10

    # Enqueues a sync that is one of many (the nightly sync, a holiday change,
    # a finals import). The worker takes high and default before low
    # (config/queue.yml), so a fan-out does not hold up mail or the syncs that
    # people start. The worker threads limit how many syncs run at once.
    def self.perform_bulk_later(user, **)
      set(queue: :low, priority: BULK_PRIORITY).perform_later(user, **)
    end

    def perform(user, force: false, backfill_historical: force, nightly: false)
      user.sync_course_schedule(force: force, backfill_historical: backfill_historical)

      # CourseCalendars::NightlySyncJob picks users by these columns. Record
      # every nightly sync, also one that changed nothing, so the user is not
      # picked again in each run.
      user.update!(calendar_needs_sync: false, last_calendar_sync_at: Time.current) if nightly
    end
  end
end
