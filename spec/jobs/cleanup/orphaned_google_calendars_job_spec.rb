# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cleanup::OrphanedGoogleCalendarsJob do
  let(:provider) { instance_double(GoogleCalendar::Provider) }
  let!(:tracked) { create(:course_calendar, external_calendar_id: "tracked-cal") }

  def listing(*ids)
    items = ids.map { |id| instance_double(Google::Apis::CalendarV3::CalendarListEntry, id: id, summary: "Synthetic #{id}") }
    instance_double(Google::Apis::CalendarV3::CalendarList, items: items)
  end

  before do
    allow(GoogleCalendar::Provider).to receive(:new).and_return(provider)
    allow(provider).to receive(:delete_calendar)
  end

  it "deletes Google calendars that are not in the database and keeps tracked ones" do
    allow(provider).to receive(:list_calendars).and_return(listing("tracked-cal", "orphan-1", "orphan-2"))

    result = described_class.perform_now

    expect(provider).to have_received(:delete_calendar).with("orphan-1")
    expect(provider).to have_received(:delete_calendar).with("orphan-2")
    expect(provider).not_to have_received(:delete_calendar).with("tracked-cal")
    expect(result).to eq(deleted: 2, skipped: 0, errors: 0)
  end

  it "does not treat a Microsoft calendar with the same id as tracked" do
    create(:course_calendar, :microsoft, external_calendar_id: "shared-id")
    allow(provider).to receive(:list_calendars).and_return(listing("shared-id"))

    result = described_class.perform_now

    expect(result[:deleted]).to eq(1)
  end

  it "does nothing when Google lists no calendars" do
    allow(provider).to receive(:list_calendars).and_return(listing)

    expect(described_class.perform_now).to eq(deleted: 0, skipped: 0, errors: 0)
    expect(provider).not_to have_received(:delete_calendar)
  end

  it "skips a calendar that Google says is already gone" do
    allow(provider).to receive(:list_calendars).and_return(listing("orphan-1"))
    allow(provider).to receive(:delete_calendar).and_raise(Google::Apis::ClientError.new("notFound", status_code: 404))

    expect(described_class.perform_now).to eq(deleted: 0, skipped: 1, errors: 0)
  end

  it "counts another client error and goes on to the next calendar" do
    allow(provider).to receive(:list_calendars).and_return(listing("orphan-1", "orphan-2"))
    allow(provider).to receive(:delete_calendar).with("orphan-1")
                                                .and_raise(Google::Apis::ClientError.new("forbidden", status_code: 403))

    expect(described_class.perform_now).to eq(deleted: 1, skipped: 0, errors: 1)
  end

  it "reports an unexpected error, counts it, and goes on" do
    allow(Rails.error).to receive(:report)
    allow(provider).to receive(:list_calendars).and_return(listing("orphan-1", "orphan-2"))
    allow(provider).to receive(:delete_calendar).with("orphan-1").and_raise(StandardError, "synthetic failure")

    result = described_class.perform_now

    expect(result).to eq(deleted: 1, skipped: 0, errors: 1)
    expect(Rails.error).to have_received(:report)
      .with(an_instance_of(StandardError), handled: true, context: { external_calendar_id: "orphan-1" })
  end
end
