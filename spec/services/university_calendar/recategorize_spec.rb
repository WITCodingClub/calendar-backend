# frozen_string_literal: true

require "rails_helper"

RSpec.describe UniversityCalendar::Recategorize do
  include ActiveJob::TestHelper

  let!(:announcement) do
    create(:university_calendar_event, summary: "Summer 2026 Final Exam Schedule Availabl", category: "finals",
                                       event_type_raw: "Calendar Announcement")
  end
  let!(:period) { create(:university_calendar_event, summary: "Final Exam Period (15-week & 2nd 7-week classes)", category: "finals") }

  before { allow(UniversityCalendar::SyncJob).to receive(:resync_users) }

  it "lists the changes and saves nothing when apply is false" do
    changes = described_class.call(apply: false)

    expect(changes.map(&:to_h)).to contain_exactly(
      { event_id: announcement.id, summary: announcement.summary, from: "finals", to: "academic" }
    )
    expect(announcement.reload.category).to eq("finals")
    expect(UniversityCalendar::SyncJob).not_to have_received(:resync_users)
  end

  it "saves the changes and resyncs for both the old and the new category" do
    described_class.call(apply: true)

    expect(announcement.reload.category).to eq("academic")
    expect(period.reload.category).to eq("finals")
    expect(UniversityCalendar::SyncJob).to have_received(:resync_users).with(contain_exactly("finals", "academic"))
  end

  it "leaves a row an admin added by hand" do
    manual = create(:university_calendar_event, ics_uid: "manual:fall-2026-finals", summary: "Final Exam Schedule Online",
                                                category: "finals")

    described_class.call(apply: true)

    expect(manual.reload.category).to eq("finals")
  end

  it "queues no sync when nothing changes" do
    announcement.update!(category: "academic")

    expect(described_class.call(apply: true)).to be_empty
    expect(UniversityCalendar::SyncJob).not_to have_received(:resync_users)
  end
end
