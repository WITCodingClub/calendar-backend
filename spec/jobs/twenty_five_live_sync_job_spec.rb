# frozen_string_literal: true

require "rails_helper"

RSpec.describe TwentyFiveLiveSyncJob, type: :job do
  describe ".in_progress?" do
    def create_job(class_name: "TwentyFiveLiveSyncJob")
      SolidQueue::Job.create!(
        class_name: class_name,
        queue_name: "default",
        active_job_id: SecureRandom.uuid,
        arguments: {}
      )
    end

    it "is false when no sync job exists" do
      expect(described_class.in_progress?).to be(false)
    end

    it "is true while a sync job is unfinished" do
      create_job

      expect(described_class.in_progress?).to be(true)
    end

    it "is false once the sync job has finished" do
      create_job.update!(finished_at: Time.current)

      expect(described_class.in_progress?).to be(false)
    end

    it "is false when the sync job failed" do
      job = create_job
      SolidQueue::FailedExecution.create!(job: job, exception: StandardError.new("25Live is down"))

      expect(described_class.in_progress?).to be(false)
    end

    it "ignores unfinished jobs of other classes" do
      create_job(class_name: "UniversityCalendarSyncJob")

      expect(described_class.in_progress?).to be(false)
    end
  end
end
