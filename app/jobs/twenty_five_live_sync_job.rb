# frozen_string_literal: true

class TwentyFiveLiveSyncJob < ApplicationJob
  queue_as :default

  # A sync is in progress while a job for it is queued or running. A failed
  # job also has no finished_at, so leave those out.
  def self.in_progress?
    SolidQueue::Job
      .where(class_name: name, finished_at: nil)
      .where.missing(:failed_execution)
      .exists?
  end

  def perform
    External::TwentyFiveLiveService.call!
  end
end
