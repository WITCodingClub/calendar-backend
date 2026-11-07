# frozen_string_literal: true

module Batches
  # A general on_finish callback for a Solid Queue batch: it logs the batch's
  # description, metadata, and totals in one line. Use it for a fan-out that
  # needs no other follow-up, so the log shows when the last job ended and
  # how many failed. A failed batch logs at warn level.
  #
  #   SolidQueue::Batch.enqueue(description: "Section links backfill", on_finish: Batches::ReportJob) { ... }
  class ReportJob < ApplicationJob
    queue_as :low

    def perform
      return Rails.logger.warn("[Batches::ReportJob] No batch") if batch.nil?

      line = { message: "Batch finished", description: batch.description, batch_id: batch.id,
               metadata: batch.metadata, total: batch.total_jobs, completed: batch.completed_jobs,
               failed: batch.failed_jobs }.to_json
      batch.failed? ? Rails.logger.warn(line) : Rails.logger.info(line)
    end
  end
end
