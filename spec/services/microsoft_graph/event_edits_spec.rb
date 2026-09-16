# frozen_string_literal: true

require "rails_helper"

RSpec.describe MicrosoftGraph::EventEdits do
  let(:zone) { Time.find_zone!("America/New_York") }
  let(:row) do
    build(:calendar_event, summary: "Synthetic Course", location: "Synthetic Hall - 101",
                           start_time: zone.local(2026, 9, 14, 9, 0), end_time: zone.local(2026, 9, 14, 10, 15),
                           recurrence: nil)
  end
  let(:remote) { JSON.parse(file_fixture("microsoft_graph/event_fetched.json").read) }

  def edits(overrides = {})
    described_class.new(row, remote.merge(overrides.deep_stringify_keys))
  end

  describe "#edited_fields" do
    it "finds no edits when Outlook matches what the app wrote" do
      expect(edits.edited_fields).to be_empty
    end

    it "finds a changed title, location and times" do
      result = edits(subject: "Renamed", location: { displayName: "Other Room" },
                     start: { dateTime: "2026-09-14T09:30:00.0000000", timeZone: "Eastern Standard Time" },
                     end: { dateTime: "2026-09-14T15:15:00.0000000", timeZone: "UTC" })

      expect(result.edited_fields).to contain_exactly("summary", "location", "start_time", "end_time")
    end

    it "reads a time in UTC" do
      result = edits(start: { dateTime: "2026-09-14T13:00:00.0000000", timeZone: "UTC" },
                     end: { dateTime: "2026-09-14T14:15:00.0000000", timeZone: "UTC" })

      expect(result.edited_fields).to be_empty
    end

    it "treats a missing location and an empty one as the same" do
      row.location = nil

      expect(edits(location: { displayName: "" }).edited_fields).to be_empty
    end

    it "compares an all-day event by its days" do
      row.start_time = zone.local(2026, 11, 26, 0, 0)
      row.end_time   = zone.local(2026, 11, 27, 23, 59)
      result = edits(isAllDay: true,
                     start: { dateTime: "2026-11-26T00:00:00.0000000", timeZone: "Eastern Standard Time" },
                     end: { dateTime: "2026-11-28T00:00:00.0000000", timeZone: "Eastern Standard Time" })

      expect(result.edited_fields).to be_empty
    end
  end

  describe "#recurrence_changed?" do
    it "is false for a single event on both sides" do
      expect(edits.recurrence_changed?).to be(false)
    end

    it "is true when the person made a single event repeat" do
      result = edits(recurrence: { pattern: { type: "daily", interval: 1 }, range: { type: "noEnd", startDate: "2026-09-14" } })

      expect(result.recurrence_changed?).to be(true)
    end
  end

  describe "#merge" do
    it "takes the person's value for each edited field only" do
      result = edits(subject: "Renamed", start: { dateTime: "2026-09-14T11:00:00.0000000", timeZone: "Eastern Standard Time" })
      data   = { summary: "App title", location: "App room", start_time: zone.local(2026, 9, 14, 9), end_time: zone.local(2026, 9, 14, 10) }

      merged = result.merge(data, %w[summary start_time])

      expect(merged).to include(summary: "Renamed", location: "App room", start_time: zone.local(2026, 9, 14, 11),
                                end_time: zone.local(2026, 9, 14, 10))
    end
  end
end
