# frozen_string_literal: true

require "rails_helper"

RSpec.describe PgheroCaptureQueryStatsJob, type: :job do
  describe "#perform" do
    it "captures query stats" do
      allow(PgHero).to receive(:capture_query_stats)

      described_class.perform_now

      expect(PgHero).to have_received(:capture_query_stats)
    end

    it "logs and does not raise when query stats are not enabled" do
      allow(PgHero).to receive(:capture_query_stats).and_raise(PgHero::NotEnabled, "Query stats not enabled")
      allow(Rails.logger).to receive(:info)

      expect { described_class.perform_now }.not_to raise_error
      expect(Rails.logger).to have_received(:info).with("PgHero query stats not enabled: Query stats not enabled")
    end
  end

  describe "database setup" do
    let(:database) { PgHero.databases.values.first }

    it "has the pg_stat_statements extension" do
      expect(database.query_stats_extension_enabled?).to be(true)
    end

    it "has the table that stores captured query stats" do
      expect(database.historical_query_stats_enabled?).to be(true)
    end
  end
end
