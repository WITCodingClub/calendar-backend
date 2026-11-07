# frozen_string_literal: true

module CourseCalendars
  class NightlySyncJob < ApplicationJob
    queue_as :low

    def perform
      base = User.joins(:course_calendars).distinct

      first_time   = base.where(last_calendar_sync_at: nil)
      needs_update = base.where(calendar_needs_sync: true).where.not(last_calendar_sync_at: nil)

      first_time_count = first_time.count
      needs_update_count = needs_update.count
      Rails.logger.info "Nightly Calendar Sync: Processing #{first_time_count + needs_update_count} users " \
                        "(#{first_time_count} first-time, #{needs_update_count} updates)"

      # One batch for the run, so its totals are logged and counted when the
      # last sync ends (CourseCalendars::BulkSyncFinishedJob).
      SolidQueue::Batch.enqueue(description: "Calendar sync: nightly", on_finish: CourseCalendars::BulkSyncFinishedJob,
                                reason: "nightly") do
        first_time.find_each do |user|
          sync_user(user, backfill_historical: true)
        end

        needs_update.find_each do |user|
          sync_user(user, backfill_historical: false)
        end
      end

      Rails.logger.info "Nightly Calendar Sync: Enqueued #{first_time_count + needs_update_count} syncs"
    end

    private

    # Each user gets a CourseCalendars::SyncJob. That job holds the per-user
    # lock, so the nightly sync cannot run at the same time as a sync that a
    # preference change starts, and the two cannot both create remote events.
    #
    # The sync does not use force. Without force, the providers update only the
    # events whose data hash changed (CalendarEvent#data_changed?), and keep
    # the edits the person made in Google or Outlook. With force, every event
    # gets an API call, and the person's edits are lost.
    def sync_user(user, backfill_historical:)
      Rails.logger.info "Enqueueing calendar sync for user #{user.id} (backfill_historical=#{backfill_historical})"

      CourseCalendars::SyncJob.perform_bulk_later(user, force: false, backfill_historical: backfill_historical, nightly: true)
    end
  end
end
