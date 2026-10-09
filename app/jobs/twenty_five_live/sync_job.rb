# frozen_string_literal: true

module TwentyFiveLive
  class SyncJob < ApplicationJob
    queue_as :default

    # A job queued before the rename still has the old class name.
    # Remove the old name with app/jobs/twenty_five_live_sync_job.rb.
    CLASS_NAMES = [ "TwentyFiveLive::SyncJob", "TwentyFiveLiveSyncJob" ].freeze

    # A sync is in progress while a job for it is queued or running. A failed
    # job also has no finished_at, so leave those out.
    def self.in_progress?
      SolidQueue::Job
        .where(class_name: CLASS_NAMES, finished_at: nil)
        .where.missing(:failed_execution)
        .exists?
    end

    def perform
      TwentyFiveLive::Client.call!
    end
  end
end
