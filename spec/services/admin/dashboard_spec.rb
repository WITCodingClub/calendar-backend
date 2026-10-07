# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Dashboard do
  subject(:dashboard) { described_class.new(user) }

  let!(:user) { create(:user, access_level: :owner, created_at: 30.days.ago) }

  # SolidQueue rows belong to the gem, so the spec builds them by hand.
  def failed_job(class_name:, message:)
    job = SolidQueue::Job.create!(queue_name: "default", class_name: class_name, arguments: {}, active_job_id: SecureRandom.uuid)
    SolidQueue::FailedExecution.create!(job: job, error: { exception_class: "RuntimeError", message: message, backtrace: [] })
  end

  describe "#sync_health" do
    it "counts calendars synced in the last day, stale ones, and never synced ones" do
      create(:course_calendar, last_synced_at: 1.hour.ago)
      create(:course_calendar, last_synced_at: 3.days.ago)
      create(:course_calendar, last_synced_at: nil)

      expect(dashboard.sync_health).to include(total: 3, healthy: 1, stale: 2, never_synced: 1)
      expect(dashboard.sync_status).to eq(:danger)
    end

    it "is ok with no calendars" do
      expect(dashboard.sync_status).to eq(:ok)
    end
  end

  describe "#recent_failed_jobs" do
    it "returns the newest failures with their job" do
      failed_job(class_name: "OldJob", message: "old")
      newest = failed_job(class_name: "NewJob", message: "boom")

      expect(dashboard.failed_jobs_count).to eq(2)
      expect(dashboard.recent_failed_jobs.first).to eq(newest)
      expect(dashboard.recent_failed_jobs.first.job.class_name).to eq("NewJob")
    end
  end

  describe "#recent_sign_ups" do
    it "lists the newest users first" do
      older = create(:user, created_at: 2.days.ago)
      newer = create(:user, created_at: 1.hour.ago)

      expect(dashboard.recent_sign_ups).to eq([ newer, older, user ])
      expect(dashboard.sign_ups_this_week).to eq(2)
    end
  end

  describe "#attention" do
    it "lists only work with a count above zero" do
      create(:finals_schedule, status: :failed)

      expect(dashboard.attention.pluck(:label)).to eq([ "Failed finals schedules" ])
    end

    it "leaves out failed catalog imports for an admin who cannot open the catalog" do
      create(:term, catalog_import_failed: true)

      expect(described_class.new(create(:user, :admin)).attention.pluck(:label)).not_to include("Failed catalog imports")
      expect(dashboard.attention.pluck(:label)).to include("Failed catalog imports")
    end
  end
end
