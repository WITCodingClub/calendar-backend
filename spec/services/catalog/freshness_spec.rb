# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::Freshness do
  around do |example|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original
  end

  def source(data_prefix) = described_class.call.find { |s| s[:data].start_with?(data_prefix) }

  it "gives the latest refresh of the sections and the course details" do
    synced = Time.zone.parse("2026-10-21 04:12")
    create(:course, banner_synced_at: synced - 1.day)
    create(:course, banner_synced_at: synced)
    create(:catalog_course, details_fetched_at: synced - 2.days)

    expect(source("Course sections")).to include(source: /Banner/, last_refreshed_at: synced.iso8601)
    expect(source("Course descriptions")).to include(last_refreshed_at: (synced - 2.days).iso8601)
  end

  it "gives no time for a source that never refreshed" do
    expect(described_class.call.pluck(:last_refreshed_at)).to eq([ nil, nil ])
  end

  it "keeps the times in the cache" do
    described_class.call
    create(:course, banner_synced_at: Time.current)

    expect(source("Course sections")[:last_refreshed_at]).to be_nil
  end

  # The schedule text says 4 AM. It must change with the recurring job.
  it "matches the schedule of the daily catalog sync" do
    recurring = YAML.load_file(Rails.root.join("config/recurring.yml"))

    expect(recurring.dig("production", "course_data_sync", "schedule")).to eq("every day at 4am")
  end
end
