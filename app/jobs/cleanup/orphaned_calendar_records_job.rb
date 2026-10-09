# frozen_string_literal: true

module Cleanup
  # Retired. This job does nothing.
  #
  # The job deleted the course calendar, and so the Google calendar, of each
  # person whose credential had an expired access token and no refresh token.
  # That person only needs to sign in again: Cleanup::OrphanedOauthCredentialsJob
  # marks them, and the calendar works again after sign-in. The job's other
  # queries looked for calendars without a credential and credentials without a
  # user, which NOT NULL foreign keys make impossible.
  #
  # The class stays so that jobs in the queue before the deploy still run.
  # Remove this file and cleanup_orphaned_calendar_records_job.rb when no
  # Cleanup::OrphanedCalendarRecordsJob or CleanupOrphanedCalendarRecordsJob
  # job is left in the queue on production.
  class OrphanedCalendarRecordsJob < ApplicationJob
    queue_as :low

    def perform
      Rails.logger.info "[Cleanup::OrphanedCalendarRecordsJob] Retired; nothing to do"
    end
  end
end
