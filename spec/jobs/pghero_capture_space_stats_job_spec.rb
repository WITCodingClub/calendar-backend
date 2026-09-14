# frozen_string_literal: true

require "rails_helper"

RSpec.describe PgheroCaptureSpaceStatsJob, type: :job do
  describe "#perform" do
    it "stores a space stats row for each relation" do
      expect { described_class.perform_now }.to change { PgHero::SpaceStats.count }.from(0)
    end

    it "logs and does not raise when space stats are not enabled" do
      allow(PgHero).to receive(:capture_space_stats).and_raise(PgHero::NotEnabled, "Space stats not enabled")
      allow(Rails.logger).to receive(:info)

      expect { described_class.perform_now }.not_to raise_error
      expect(Rails.logger).to have_received(:info).with("PgHero space stats not enabled: Space stats not enabled")
    end
  end

  describe "database setup" do
    it "has the table that stores captured space stats" do
      expect(PgHero.databases.values.first.space_stats_enabled?).to be(true)
    end
  end
end
