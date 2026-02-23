# frozen_string_literal: true

# Background job to process uploaded finals schedule PDFs
# Parses PDF content and creates/updates FinalExam records
class FinalsScheduleProcessJob < ApplicationJob
  queue_as :default

  # Prevent concurrent processing of the same schedule
  limits_concurrency to: 1, key: ->(finals_schedule) { "finals_schedule_process_#{finals_schedule.id}" }

  # If the FinalsSchedule was deleted before this job ran (e.g. user cancelled the upload),
  # just discard the job rather than letting it fail.
  rescue_from(ActiveJob::DeserializationError) do |error|
    Rails.logger.warn("FinalsScheduleProcessJob: skipping job, record no longer exists (#{error.message})")
  end

  def perform(finals_schedule)
    finals_schedule.process!
  rescue => e
    Rails.logger.error("Failed to process finals schedule #{finals_schedule.id}: #{e.message}")
    Rails.logger.error(e.backtrace.first(10).join("\n"))
    raise
  end

end
