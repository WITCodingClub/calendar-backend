# frozen_string_literal: true

class NightlyCalendarSyncJob < ApplicationJob
  queue_as :low

  def perform
    users_to_sync = User.joins(:google_calendars)
                        .where(calendar_needs_sync: true)
                        .or(
                          User.joins(:google_calendars)
                              .where(last_calendar_sync_at: nil)
                        )
                        .distinct

    Rails.logger.info "Nightly Calendar Sync: Processing #{users_to_sync.count} users"

    users_to_sync.find_each do |user|
      Rails.logger.info "Syncing calendar for user #{user.id}"

      user.sync_course_schedule

      user.update!(
        calendar_needs_sync: false,
        last_calendar_sync_at: Time.current
      )

      Rails.logger.info "Successfully synced calendar for user #{user.id}"
    rescue => e
      Rails.logger.error "Failed to sync calendar for user #{user.id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end

    Rails.logger.info "Nightly Calendar Sync: Completed"
  end
end
