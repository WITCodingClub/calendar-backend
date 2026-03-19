# frozen_string_literal: true

require "rails_helper"

RSpec.describe PgheroCaptureQueryStatsJob do
  describe "queue assignment" do
    it "is assigned to the low queue" do
      expect(described_class.new.queue_name).to eq("low")
    end
  end

  describe "#perform" do
    it "captures query stats" do
      allow(PgHero).to receive(:capture_query_stats)

      described_class.perform_now

      expect(PgHero).to have_received(:capture_query_stats)
    end

    it "swallows PgHero::NotEnabled and logs context" do
      allow(PgHero).to receive(:capture_query_stats).and_raise(PgHero::NotEnabled, "Query stats not enabled")
      allow(Rails.logger).to receive(:info)

      expect { described_class.perform_now }.not_to raise_error
      expect(Rails.logger).to have_received(:info).with(/PgHero query stats not enabled/)
    end
  end
end
