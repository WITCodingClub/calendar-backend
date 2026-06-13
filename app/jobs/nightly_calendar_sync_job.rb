# frozen_string_literal: true

class NightlyCalendarSyncJob < ApplicationJob
  queue_as :low

  def perform
    base = User.joins(:google_calendars).distinct

    # Never-synced users: first full sync, no force needed (nothing stale to skip)
    first_time = base.where(last_calendar_sync_at: nil)
    # Previously-synced users with a data change: force to bypass staleness cache
    needs_update = base.where(calendar_needs_sync: true).where.not(last_calendar_sync_at: nil)

    total = first_time.count + needs_update.count
    Rails.logger.info "Nightly Calendar Sync: Processing #{total} users (#{first_time.count} first-time, #{needs_update.count} updates)"

    first_time.find_each do |user|
      sync_user(user, force: false, backfill_historical: true)
    end

    needs_update.find_each do |user|
      sync_user(user, force: true, backfill_historical: false)
    end

    Rails.logger.info "Nightly Calendar Sync: Completed"
  end

  private

  def sync_user(user, force:, backfill_historical:)
    Rails.logger.info "Syncing calendar for user #{user.id} (force=#{force}, backfill_historical=#{backfill_historical})"

    user.sync_course_schedule(force: force, backfill_historical: backfill_historical)

    user.update!(
      calendar_needs_sync: false,
      last_calendar_sync_at: Time.current
    )

    Rails.logger.info "Successfully synced calendar for user #{user.id}"
  rescue => e
    Rails.logger.error "Failed to sync calendar for user #{user.id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end
end
