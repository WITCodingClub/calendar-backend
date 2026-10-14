# frozen_string_literal: true

module CourseCalendars
  class NightlySyncJob < ApplicationJob
    queue_as :low

    # Solid Queue runs the job with the lowest number first. Other jobs use 0.
    SYNC_PRIORITY = 10

    def perform
      base = User.joins(:course_calendars).distinct

      # Never-synced users: first full sync, no force needed (nothing stale to skip)
      first_time = base.where(last_calendar_sync_at: nil)
      # Previously-synced users with a data change: force to bypass staleness cache
      needs_update = base.where(calendar_needs_sync: true).where.not(last_calendar_sync_at: nil)

      first_time_count = first_time.count
      needs_update_count = needs_update.count
      Rails.logger.info "Nightly Calendar Sync: Processing #{first_time_count + needs_update_count} users " \
                        "(#{first_time_count} first-time, #{needs_update_count} updates)"

      first_time.find_each do |user|
        sync_user(user, force: false, backfill_historical: true)
      end

      needs_update.find_each do |user|
        sync_user(user, force: true, backfill_historical: false)
      end

      Rails.logger.info "Nightly Calendar Sync: Enqueued #{first_time_count + needs_update_count} syncs"
    end

    private

    # Each user gets a CourseCalendars::SyncJob. That job holds the per-user
    # lock, so the nightly sync cannot run at the same time as a sync that a
    # preference change starts, and the two cannot both create remote events.
    #
    # The low priority puts the nightly syncs behind the syncs that people
    # start. The worker threads limit how many syncs run at the same time.
    def sync_user(user, force:, backfill_historical:)
      Rails.logger.info "Enqueueing calendar sync for user #{user.id} (force=#{force}, backfill_historical=#{backfill_historical})"

      CourseCalendars::SyncJob.set(queue: :low, priority: SYNC_PRIORITY)
                              .perform_later(user, force: force, backfill_historical: backfill_historical, nightly: true)
    end
  end
end
