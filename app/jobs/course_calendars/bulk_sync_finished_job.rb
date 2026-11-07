# frozen_string_literal: true

module CourseCalendars
  # The on_finish callback of a bulk calendar sync batch
  # (CourseCalendars::SyncJob.perform_bulk_in_batch). It logs how many syncs
  # completed and failed, and counts them in calendar_bulk_calendar_syncs_total
  # by reason, so a nightly run that failed for many users shows on the
  # dashboard.
  class BulkSyncFinishedJob < ApplicationJob
    queue_as :default

    def perform
      return Rails.logger.warn("[CourseCalendars::BulkSyncFinishedJob] No batch") if batch.nil?

      reason = batch.metadata[:reason].presence || "unknown"
      Yabeda.calendar.bulk_calendar_syncs_total.increment({ reason: reason, result: "completed" }, by: batch.completed_jobs)
      Yabeda.calendar.bulk_calendar_syncs_total.increment({ reason: reason, result: "failed" }, by: batch.failed_jobs)

      Rails.logger.info({ message: "Bulk calendar sync finished", reason: reason, batch_id: batch.id,
                          total: batch.total_jobs, completed: batch.completed_jobs, failed: batch.failed_jobs }.to_json)
    end
  end
end
