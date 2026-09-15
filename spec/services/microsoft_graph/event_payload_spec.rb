# frozen_string_literal: true

require "rails_helper"

RSpec.describe MicrosoftGraph::EventPayload do
  let(:zone) { Time.find_zone!("America/New_York") }

  let(:weekly_class) do
    {
      summary:     "Synthetic Course",
      description: "COMP-1000-01",
      location:    "Synthetic Hall - 101",
      start_time:  zone.local(2026, 9, 14, 9, 0),
      end_time:    zone.local(2026, 9, 14, 10, 15),
      all_day:     false,
      recurrence:  [
        "RRULE:FREQ=WEEKLY;UNTIL=20261212T045959Z;BYDAY=MO,WE",
        "EXDATE;TZID=America/New_York:20261012T090000"
      ]
    }
  end

  describe ".build" do
    it "sends local wall-clock times in the Eastern time zone" do
      payload = described_class.build(weekly_class)

      expect(payload).to include(
        subject:  "Synthetic Course",
        body:     { contentType: "text", content: "COMP-1000-01" },
        location: { displayName: "Synthetic Hall - 101" },
        isAllDay: false,
        start:    { dateTime: "2026-09-14T09:00:00", timeZone: "Eastern Standard Time" },
        end:      { dateTime: "2026-09-14T10:15:00", timeZone: "Eastern Standard Time" }
      )
    end

    it "turns a weekly RRULE into a patterned recurrence that ends on the local UNTIL date" do
      recurrence = described_class.build(weekly_class)[:recurrence]

      expect(recurrence).to eq(
        pattern: { type: "weekly", interval: 1, daysOfWeek: %w[monday wednesday], firstDayOfWeek: "sunday" },
        range:   { type: "endDate", startDate: "2026-09-14", endDate: "2026-12-11", recurrenceTimeZone: "Eastern Standard Time" }
      )
    end

    it "sends no recurrence for a single event" do
      expect(described_class.build(weekly_class.merge(recurrence: nil))[:recurrence]).to be_nil
    end

    it "sends an all-day event from midnight to midnight the day after" do
      payload = described_class.build(
        summary: "Fall Break", start_time: zone.local(2026, 10, 12), end_time: zone.local(2026, 10, 12, 23, 59, 59), all_day: true
      )

      expect(payload).to include(
        isAllDay: true,
        start:    { dateTime: "2026-10-12T00:00:00", timeZone: "Eastern Standard Time" },
        end:      { dateTime: "2026-10-13T00:00:00", timeZone: "Eastern Standard Time" }
      )
    end

    it "keeps the earliest reminder, because Graph has one reminder per event" do
      payload = described_class.build(weekly_class.merge(reminder_settings: [
        { "time" => "1", "type" => "hours", "method" => "popup" },
        { "time" => "15", "type" => "minutes", "method" => "notification" }
      ]))

      expect(payload).to include(isReminderOn: true, reminderMinutesBeforeStart: 15)
    end

    it "turns the reminder off for an empty list" do
      expect(described_class.build(weekly_class.merge(reminder_settings: []))).to include(isReminderOn: false)
    end

    it "leaves the Outlook default reminder alone when no reminders were resolved" do
      expect(described_class.build(weekly_class).keys).not_to include(:isReminderOn)
    end

    it "maps private visibility to private sensitivity" do
      expect(described_class.build(weekly_class.merge(visibility: "private"))).to include(sensitivity: "private")
      expect(described_class.build(weekly_class.merge(visibility: "public"))).to include(sensitivity: "normal")
    end
  end

  describe ".excluded_dates" do
    it "reads the local dates from EXDATE entries" do
      expect(described_class.excluded_dates(weekly_class[:recurrence])).to eq([ Date.new(2026, 10, 12) ])
    end

    it "is empty without a recurrence" do
      expect(described_class.excluded_dates(nil)).to eq([])
    end
  end
end
