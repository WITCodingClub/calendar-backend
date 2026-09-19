# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260919220000_remove_api_version_flipper_flags")

# The rows are built by hand, because FlipperFlags no longer names these flags.
RSpec.describe RemoveApiVersionFlipperFlags do
  subject(:migration) { described_class.new }

  let(:connection) { ActiveRecord::Base.connection }

  before do
    migration.verbose = false
    %w[2025_10_04_v1 2025_11_12_v2 debug_mode].each do |key|
      connection.execute(<<~SQL.squish)
        INSERT INTO flipper_features (key, created_at, updated_at)
        VALUES (#{connection.quote(key)}, now(), now())
        ON CONFLICT (key) DO NOTHING
      SQL
      connection.execute(<<~SQL.squish)
        INSERT INTO flipper_gates (feature_key, key, value, created_at, updated_at)
        VALUES (#{connection.quote(key)}, 'boolean', 'true', now(), now())
        ON CONFLICT DO NOTHING
      SQL
    end
  end

  def feature_keys = connection.select_values("SELECT key FROM flipper_features")
  def gate_keys = connection.select_values("SELECT feature_key FROM flipper_gates")

  it "deletes the v1 and v2 flags and their gates" do
    migration.migrate(:up)

    expect(feature_keys).not_to include("2025_10_04_v1", "2025_11_12_v2")
    expect(gate_keys).not_to include("2025_10_04_v1", "2025_11_12_v2")
  end

  it "keeps the other flags" do
    migration.migrate(:up)

    expect(feature_keys).to include("debug_mode")
    expect(gate_keys).to include("debug_mode")
  end
end
