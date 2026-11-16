# frozen_string_literal: true

require "rails_helper"

RSpec.describe UniversityCalendar::BackfillJob do
  let(:no_changes) { { created: 0, updated: 0, cancelled: 0, changed_categories: [] } }

  before { allow(UniversityCalendar::SyncJob).to receive(:resync_users) }

  def run_with(result)
    allow(UniversityCalendar::IcsImport).to receive(:call).and_return(result)
    described_class.perform_now(Date.new(2026, 1, 1), Date.new(2026, 6, 30))
  end

  it "imports the date range from the backfill URL" do
    run_with(no_changes)

    expect(UniversityCalendar::IcsImport).to have_received(:call)
      .with(ics_url: UniversityCalendar::IcsImport.backfill_url(Date.new(2026, 1, 1), Date.new(2026, 6, 30)))
  end

  it "resyncs the calendars for the categories that changed" do
    run_with(no_changes.merge(updated: 1, changed_categories: %w[finals academic]))

    expect(UniversityCalendar::SyncJob).to have_received(:resync_users).with(%w[finals academic])
  end

  it "resyncs nothing when the import changed nothing" do
    run_with(no_changes)

    expect(UniversityCalendar::SyncJob).not_to have_received(:resync_users)
  end
end
