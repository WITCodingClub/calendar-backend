# frozen_string_literal: true

module Cleanup
  # Deletes course calendars whose credential has an expired access token and
  # no refresh token.
  #
  # The job no longer looks for calendars without a credential, or credentials
  # without a user. NOT NULL foreign keys on calendars.oauth_credential_id and
  # oauth_credentials.user_id make those rows impossible.
  class OrphanedCalendarRecordsJob < ApplicationJob
    queue_as :low

    REASON = "Expired token without refresh capability"

    def perform
      Rails.logger.info "[Cleanup::OrphanedCalendarRecordsJob] Starting orphaned calendar cleanup"

      deleted_count = 0
      error_count = 0

      orphaned_calendars = CourseCalendar.joins(:oauth_credential)
                                         .where(oauth_credentials: { token_expires_at: ..Time.current, refresh_token: nil })

      Rails.logger.info "[Cleanup::OrphanedCalendarRecordsJob] Found #{orphaned_calendars.size} orphaned calendars"

      orphaned_calendars.find_each do |calendar|
        Rails.logger.info "[Cleanup::OrphanedCalendarRecordsJob] Deleting calendar #{calendar.id} " \
                          "(external_calendar_id: #{calendar.external_calendar_id}) - Reason: #{REASON}"

        calendar.destroy!
        deleted_count += 1
      rescue => e
        error_count += 1
        Rails.error.report(e, handled: true, context: { course_calendar_id: calendar.id })
      end

      Rails.logger.info "[Cleanup::OrphanedCalendarRecordsJob] Completed: #{deleted_count} deleted, #{error_count} errors"

      { deleted: deleted_count, errors: error_count }
    end
  end
end
