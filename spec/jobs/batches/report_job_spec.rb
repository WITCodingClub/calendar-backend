# frozen_string_literal: true

require "rails_helper"

RSpec.describe Batches::ReportJob do
  def run_for(batch)
    job = described_class.new
    job.callback_batch_id = batch.id
    job.perform_now
  end

  def finished_batch(failed:)
    SolidQueue::Batch.create!(description: "Section links backfill", metadata: { terms: 3 },
                              total_jobs: 3, completed_jobs: 3 - failed, failed_jobs: failed,
                              finished_at: Time.current, failed_at: (Time.current if failed.positive?))
  end

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
  end

  it "logs the description, metadata and totals of the batch" do
    run_for(finished_batch(failed: 0))

    expect(Rails.logger).to have_received(:info)
      .with(a_string_including('"description":"Section links backfill"', '"terms":3', '"total":3', '"failed":0'))
  end

  it "logs a failed batch as a warning" do
    run_for(finished_batch(failed: 1))

    expect(Rails.logger).to have_received(:warn).with(a_string_including('"failed":1'))
  end

  it "does nothing without a batch" do
    described_class.perform_now

    expect(Rails.logger).to have_received(:warn).with("[Batches::ReportJob] No batch")
  end
end
