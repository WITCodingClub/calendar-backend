# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseCalendars::BulkSyncFinishedJob do
  def count(result) = Yabeda.calendar.bulk_calendar_syncs_total.get(reason: "nightly", result: result) || 0

  def finished_batch(total:, failed:)
    SolidQueue::Batch.create!(description: "Calendar sync: nightly", metadata: { reason: "nightly" },
                              total_jobs: total, completed_jobs: total - failed, failed_jobs: failed,
                              finished_at: Time.current, failed_at: (Time.current if failed.positive?))
  end

  def run_for(batch)
    job = described_class.new
    job.callback_batch_id = batch.id
    job.perform_now
  end

  it "counts the completed and failed syncs of the batch by reason" do
    completed_before = count("completed")
    failed_before = count("failed")

    run_for(finished_batch(total: 5, failed: 2))

    expect(count("completed") - completed_before).to eq(3)
    expect(count("failed") - failed_before).to eq(2)
  end

  it "logs the totals" do
    allow(Rails.logger).to receive(:info)

    run_for(finished_batch(total: 4, failed: 0))

    expect(Rails.logger).to have_received(:info).with(a_string_including('"reason":"nightly"', '"total":4', '"failed":0'))
  end

  it "does nothing without a batch" do
    expect { described_class.perform_now }.not_to raise_error
  end
end
