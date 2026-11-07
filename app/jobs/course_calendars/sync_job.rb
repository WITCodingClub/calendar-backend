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
    # a finals import, a rake task over all users). A fan-out on high would
    # hold up every default job, mail too, because the worker takes high first
    # (config/queue.yml). On default at a higher number, mail and the other
    # default jobs go first.
    #
    # Not on low: Solid Queue takes the per-user lock at enqueue, so a sync
    # that the person starts waits until their bulk sync runs. Behind a low
    # backlog (catalog imports, embeddings) that wait could pass the lock
    # duration, and then both syncs run at once.
    def self.perform_bulk_later(user, **)
      set(queue: :default, priority: BULK_PRIORITY).perform_later(user, **)
    end

    # Queues a bulk sync for each user as one Solid Queue batch, and returns
    # the batch. When the last sync ends, CourseCalendars::BulkSyncFinishedJob
    # logs the totals and counts them in calendar_bulk_calendar_syncs_total.
    # `reason` is a short label for the metric (nightly, holidays, finals).
    # Pass the description to find the batch again, as the finals page does.
    def self.perform_bulk_in_batch(users, reason:, description: "Calendar sync: #{reason}", **)
      SolidQueue::Batch.enqueue(description: description, on_finish: CourseCalendars::BulkSyncFinishedJob, reason: reason) do
        users.find_each { |user| perform_bulk_later(user, **) }
      end
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
