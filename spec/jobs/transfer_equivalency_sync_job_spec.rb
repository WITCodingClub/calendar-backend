# frozen_string_literal: true

require "rails_helper"

RSpec.describe TransferEquivalencySyncJob do
  include ActiveJob::TestHelper

  describe "#perform" do
    let(:sync_result) do
      { universities_synced: 5, courses_synced: 10, equivalencies_synced: 8, errors: [] }
    end

    before do
      allow(Transfer::EquivalencySyncService).to receive(:call).and_return(sync_result)
    end

    it "calls Transfer::EquivalencySyncService" do
      expect(Transfer::EquivalencySyncService).to receive(:call)
      described_class.new.perform
    end

    it "returns the sync result" do
      result = described_class.new.perform
      expect(result).to eq(sync_result)
    end

    context "when service returns errors" do
      let(:sync_result) do
        { universities_synced: 3, courses_synced: 5, equivalencies_synced: 2, errors: ["WIT course not found for: MATH 9999"] }
      end

      it "completes without raising" do
        expect { described_class.new.perform }.not_to raise_error
      end
    end
  end

  describe "queue configuration" do
    it "uses the default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end

  describe "enqueueing" do
    it "can be enqueued" do
      expect {
        described_class.perform_later
      }.to have_enqueued_job(described_class)
    end
  end
end
