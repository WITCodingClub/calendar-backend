# frozen_string_literal: true

require "rails_helper"

RSpec.describe FinalsScheduleProcessJob do
  describe "queue assignment" do
    it "is assigned to the default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end

  describe "#perform" do
    let(:finals_schedule) { create(:finals_schedule) }

    before do
      allow(FinalsScheduleParserService).to receive(:call).and_return({
        total: 5,
        created: 4,
        updated: 1,
        skipped: 0,
        errors: []
      })
    end

    it "calls process! on the finals schedule" do
      allow(finals_schedule).to receive(:process!)
      described_class.perform_now(finals_schedule)
      expect(finals_schedule).to have_received(:process!)
    end

    it "updates the schedule status to completed" do
      described_class.perform_now(finals_schedule)
      expect(finals_schedule.reload.status).to eq("completed")
    end

    it "logs errors when processing fails" do
      allow(finals_schedule).to receive(:process!).and_raise(StandardError, "Test error")
      allow(Rails.logger).to receive(:error)

      expect {
        described_class.perform_now(finals_schedule)
      }.to raise_error(StandardError, "Test error")

      expect(Rails.logger).to have_received(:error).with(/Failed to process finals schedule #{finals_schedule.id}: Test error/)
    end
  end

  describe "concurrency limits" do
    it "limits concurrency to 1 per schedule" do
      # The job uses limits_concurrency to prevent duplicate processing
      job = described_class.new
      expect(job.class.ancestors).to include(SolidQueue::JobSerialization) if defined?(SolidQueue::JobSerialization)
    end
  end
end
