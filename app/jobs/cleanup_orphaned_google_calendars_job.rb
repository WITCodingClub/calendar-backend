# frozen_string_literal: true

class CleanupOrphanedGoogleCalendarsJob < ApplicationJob
  queue_as :low

  def perform
    Rails.logger.info "[CleanupOrphanedGoogleCalendarsJob] Starting cleanup of Google calendars not in database"

    service = GoogleCalendarService.new
    google_calendars = service.list_calendars

    # Get all calendar IDs from database
    db_calendar_ids = GoogleCalendar.pluck(:google_calendar_id)

    deleted_count = 0
    error_count = 0
    skipped_count = 0

    google_calendars.items.each do |cal|
      next if db_calendar_ids.include?(cal.id)

      begin
        Rails.logger.info "[CleanupOrphanedGoogleCalendarsJob] Deleting orphaned calendar: #{cal.id} - #{cal.summary}"
        service.delete_calendar(cal.id)
        deleted_count += 1
      rescue Google::Apis::ClientError => e
        if e.status_code == 404
          Rails.logger.warn "[CleanupOrphanedGoogleCalendarsJob] Calendar not found (already deleted): #{cal.id}"
          skipped_count += 1
        else
          Rails.logger.error "[CleanupOrphanedGoogleCalendarsJob] Failed to delete calendar #{cal.id}: #{e.message}"
          error_count += 1
        end
      rescue => e
        Rails.logger.error "[CleanupOrphanedGoogleCalendarsJob] Error deleting calendar #{cal.id}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        error_count += 1
      end
    end

    Rails.logger.info "[CleanupOrphanedGoogleCalendarsJob] Completed: " \
                      "#{deleted_count} deleted, #{skipped_count} skipped, #{error_count} errors"

    { deleted: deleted_count, skipped: skipped_count, errors: error_count }
  end

end
