# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendar::EventEdits do
  let(:zone)  { Time.find_zone!("America/New_York") }
  let(:start) { zone.local(2026, 9, 15, 10) }
  let(:row) do
    build(:calendar_event, summary: "Synthetic Lecture", location: "Synthetic Hall", start_time: start, end_time: start + 1.hour,
                           recurrence: [ "RRULE:FREQ=WEEKLY;BYDAY=TU" ])
  end

  def remote_event(**overrides)
    Google::Apis::CalendarV3::Event.new(
      summary:    "Synthetic Lecture",
      location:   "Synthetic Hall",
      start:      Google::Apis::CalendarV3::EventDateTime.new(date_time: start.iso8601),
      end:        Google::Apis::CalendarV3::EventDateTime.new(date_time: (start + 1.hour).iso8601),
      recurrence: [ "RRULE:FREQ=WEEKLY;BYDAY=TU" ],
      **overrides
    )
  end

  describe ".parse_time" do
    it "reads a date time string in Eastern time" do
      time = described_class.parse_time(Google::Apis::CalendarV3::EventDateTime.new(date_time: "2026-09-15T14:00:00Z"))

      expect(time).to eq(zone.local(2026, 9, 15, 10))
      expect(time.time_zone.name).to eq("America/New_York")
    end

    it "reads a date of an all-day event" do
      expect(described_class.parse_time(Google::Apis::CalendarV3::EventDateTime.new(date: "2026-10-12"))).to eq(Time.zone.parse("2026-10-12"))
    end

    it "reads a DateTime object" do
      value = DateTime.new(2026, 9, 15, 14, 0, 0)

      expect(described_class.parse_time(Google::Apis::CalendarV3::EventDateTime.new(date_time: value))).to eq(zone.local(2026, 9, 15, 10))
    end

    it "gives nil for no time" do
      expect(described_class.parse_time(nil)).to be_nil
      expect(described_class.parse_time(Google::Apis::CalendarV3::EventDateTime.new)).to be_nil
    end
  end

  describe "#edited_fields" do
    it "finds no edit when Google has what the row has" do
      expect(described_class.new(row, remote_event).edited_fields).to eq([])
    end

    it "finds each changed field" do
      remote = remote_event(summary: "Edited", location: "Elsewhere", description: "My notes",
                            start: Google::Apis::CalendarV3::EventDateTime.new(date_time: (start + 30.minutes).iso8601),
                            end: Google::Apis::CalendarV3::EventDateTime.new(date_time: (start + 2.hours).iso8601))

      expect(described_class.new(row, remote).edited_fields).to eq(%w[summary location start_time end_time])
    end

    it "does not count the description the app wrote" do
      expect(described_class.new(row, remote_event(description: "CRN 10001")).edited_fields).to eq([])
    end

    context "with an all-day event" do
      let(:day) { zone.local(2026, 11, 26) }
      let(:row) { build(:calendar_event, summary: "Synthetic Lecture", location: "Synthetic Hall", start_time: day, end_time: day.end_of_day) }

      def all_day_event(start_date, end_date)
        remote_event(start: Google::Apis::CalendarV3::EventDateTime.new(date: start_date),
                     end: Google::Apis::CalendarV3::EventDateTime.new(date: end_date))
      end

      it "reads the end date Google gives as the day after the last day" do
        expect(described_class.new(row, all_day_event("2026-11-26", "2026-11-27")).edited_fields).to eq([])
      end

      it "finds a moved last day" do
        edits = described_class.new(row, all_day_event("2026-11-26", "2026-11-28"))

        expect(edits.edited_fields).to eq(%w[end_time])
        expect(edits.merge({}, %w[end_time])).to eq(end_time: zone.local(2026, 11, 27))
      end
    end

    it "counts a time that only one side has as an edit" do
      row.start_time = nil

      expect(described_class.new(row, remote_event).edited_fields).to eq(%w[start_time])
    end
  end

  describe "#recurrence_changed?" do
    it "ignores the order of the rules" do
      row.recurrence = [ "RRULE:FREQ=WEEKLY;BYDAY=TU", "EXDATE:20261013T100000" ]
      remote         = remote_event(recurrence: [ "EXDATE:20261013T100000", "RRULE:FREQ=WEEKLY;BYDAY=TU" ])

      expect(described_class.new(row, remote).recurrence_changed?).to be(false)
    end

    it "finds a changed rule" do
      expect(described_class.new(row, remote_event(recurrence: [ "RRULE:FREQ=WEEKLY;BYDAY=TH" ])).recurrence_changed?).to be(true)
    end

    it "treats an empty list and no list as the same" do
      row.recurrence = nil

      expect(described_class.new(row, remote_event(recurrence: [])).recurrence_changed?).to be(false)
    end
  end

  describe "#merge" do
    it "puts the person's value in place of each edited field only" do
      remote = remote_event(summary: "Edited", description: "My notes",
                            end: Google::Apis::CalendarV3::EventDateTime.new(date_time: (start + 2.hours).iso8601))
      data   = { summary: "Synthetic Lecture", description: "CRN 10001", location: "New Hall", end_time: start + 1.hour }

      merged = described_class.new(row, remote).merge(data, %w[summary description end_time])

      expect(merged).to eq(summary: "Edited", description: "CRN 10001", location: "New Hall", end_time: start + 2.hours)
      expect(data[:summary]).to eq("Synthetic Lecture")
    end
  end

  describe "#remote_row_attributes" do
    it "gives the row the event as the person left it, with the recurrence the app wrote" do
      remote = remote_event(summary: "Edited", recurrence: [ "RRULE:FREQ=WEEKLY;BYDAY=TH" ])

      attributes = described_class.new(row, remote).remote_row_attributes

      expected_data = { summary: "Edited", location: "Synthetic Hall", start_time: start, end_time: start + 1.hour }
      expect(attributes).to include(expected_data)
      expect(attributes).not_to have_key(:recurrence)
      expect(attributes[:event_data_hash]).to eq(CalendarEvent.generate_data_hash(expected_data.merge(recurrence: row.recurrence)))
      expect(attributes[:last_synced_at]).to be_within(1.minute).of(Time.current)
    end
  end
end
