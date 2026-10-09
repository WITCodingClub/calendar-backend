# frozen_string_literal: true

module Cleanup
  class OrphanedGoogleCalendarsJob < ApplicationJob
    queue_as :low

    def perform
      Rails.logger.info "[Cleanup::OrphanedGoogleCalendarsJob] Starting cleanup of Google calendars not in database"

      service = GoogleCalendar::Provider.new
      google_api_calendars = service.list_calendars

      db_calendar_ids = CourseCalendar.google.pluck(:external_calendar_id)

      deleted_count = 0
      error_count = 0
      skipped_count = 0

      google_api_calendars.items.each do |cal|
        next if db_calendar_ids.include?(cal.id)

        Rails.logger.info "[Cleanup::OrphanedGoogleCalendarsJob] Deleting orphaned calendar: #{cal.id} - #{cal.summary}"
        service.delete_calendar(cal.id)
        deleted_count += 1
      rescue Google::Apis::ClientError => e
        if e.status_code == 404
          Rails.logger.warn "[Cleanup::OrphanedGoogleCalendarsJob] Calendar not found (already deleted): #{cal.id}"
          skipped_count += 1
        else
          Rails.logger.error "[Cleanup::OrphanedGoogleCalendarsJob] Failed to delete calendar #{cal.id}: #{e.message}"
          error_count += 1
        end
      rescue => e
        Rails.logger.error "[Cleanup::OrphanedGoogleCalendarsJob] Error deleting calendar #{cal.id}: #{e.message}"
        error_count += 1
      end

      Rails.logger.info "[Cleanup::OrphanedGoogleCalendarsJob] Completed: " \
                        "#{deleted_count} deleted, #{skipped_count} skipped, #{error_count} errors"

      { deleted: deleted_count, skipped: skipped_count, errors: error_count }
    end
  end
end
