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

  let(:synced) { Time.zone.parse("2026-10-21 04:12") }
  let(:term) { create(:term, sections_synced_at: synced, details_synced_at: synced - 1.day) }

  before { allow(Term).to receive(:current).and_return(term) }

  def source(key) = described_class.call([ key ]).first

  it "gives the time each term's run finished for the section and course detail sources" do
    expect(source(:sections)).to include(source: /Banner/)
    expect(source(:sections)[:terms]).to eq([ { term_uid: term.uid, term: term.name, last_refreshed_at: synced.iso8601 } ])
    expect(source(:course_details)[:terms].first[:last_refreshed_at]).to eq((synced - 1.day).iso8601)
  end

  # A student's own courses refresh when the extension processes a term, so
  # one fresh course says nothing about the rest.
  it "ignores the confirmation time of single courses" do
    create(:course, term: term, banner_synced_at: Time.current)

    expect(source(:sections)[:terms].first[:last_refreshed_at]).to eq(synced.iso8601)
  end

  it "gives the latest completed finals schedule of each term" do
    create(:finals_schedule, term: term, status: :completed, processed_at: synced - 2.days)
    create(:finals_schedule, term: term, status: :failed, processed_at: synced)

    expect(source(:finals)[:terms].first[:last_refreshed_at]).to eq((synced - 2.days).iso8601)
  end

  it "gives the latest fetch of the university calendar" do
    create(:university_calendar_event, last_fetched_at: synced)

    expect(source(:university_calendar)).to include(source: /25Live/, last_refreshed_at: synced.iso8601)
  end

  it "gives no time for a source that never refreshed" do
    term.update!(sections_synced_at: nil)

    expect(source(:sections)[:terms].first[:last_refreshed_at]).to be_nil
    expect(source(:university_calendar)[:last_refreshed_at]).to be_nil
  end

  it "keeps the times in the cache" do
    source(:sections)
    term.update!(sections_synced_at: Time.current)

    expect(source(:sections)[:terms].first[:last_refreshed_at]).to eq(synced.iso8601)
  end

  # The schedule text gives these times. It must change with the recurring jobs.
  it "matches the schedules of the recurring syncs" do
    recurring = YAML.load_file(Rails.root.join("config/recurring.yml"))

    expect(recurring.dig("production", "course_data_sync", "schedule")).to eq("every day at 4am")
    expect(recurring.dig("production", "university_calendar_sync", "schedule")).to eq("every saturday at 2am")
    expect(recurring.dig("production", "degree_requirements_current_year", "schedule")).to eq("every month on the 2nd at 3am")
    expect(recurring.dig("production", "term_electives_import", "schedule")).to eq("every day at 3:30am")
  end

  it "gives the time of the newest catalog import" do
    create(:catalog_year, :imported, start_year: 2023, imported_at: synced - 1.day)
    create(:catalog_year, :imported, start_year: 2024, imported_at: synced)

    expect(source(:degree_requirements)).to include(source: "Wentworth academic catalog (catalog.wit.edu)",
                                                     last_refreshed_at: synced.iso8601)
  end

  it "gives the time the elective lists were last read" do
    create(:term_elective_list, fetched_at: synced - 1.day)
    create(:term_elective_list, fetched_at: synced)

    expect(source(:term_electives)).to include(source: "Wentworth Registrar elective lists (PDF)", last_refreshed_at: synced.iso8601)
  end
end
