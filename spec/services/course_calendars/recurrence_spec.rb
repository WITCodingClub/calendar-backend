# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseCalendars::Recurrence do
  include ActiveSupport::Testing::TimeHelpers

  let(:zone) { SchoolTimeZone.zone }
  let(:lines) do
    [ "RRULE:FREQ=WEEKLY;UNTIL=20261210T045959Z;BYDAY=MO", "EXDATE;TZID=America/New_York:20261012T090000" ]
  end

  describe ".until_end_of" do
    it "ends at the end of the last local day, as UTC" do
      recurrence = described_class.until_end_of(IceCube::Rule.weekly.day(:monday), Date.new(2026, 12, 9))

      expect(recurrence.lines).to eq([ "RRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20261210T045959Z" ])
    end
  end

  describe ".parse" do
    it "reads back the lines it wrote" do
      expect(described_class.parse(lines).lines).to eq(lines)
    end

    it "reads the rule parts" do
      expect(described_class.parse(lines)).to have_attributes(frequency: "WEEKLY", interval: 1, days: [ "MO" ],
                                                              until_date: Date.new(2026, 12, 9),
                                                              excluded_dates: [ Date.new(2026, 10, 12) ])
    end

    it "is nil without an RRULE" do
      expect(described_class.parse(nil)).to be_nil
    end

    it "reads a date-only EXDATE" do
      expect(described_class.parse([ lines.first, "EXDATE;VALUE=DATE:20261012" ]).excluded_dates).to eq([ Date.new(2026, 10, 12) ])
    end
  end

  describe "#ended?" do
    it "is true after UNTIL" do
      travel_to(zone.local(2026, 12, 11)) { expect(described_class.parse(lines)).to be_ended }
    end

    it "is false without UNTIL" do
      expect(described_class.parse([ "RRULE:FREQ=DAILY" ])).not_to be_ended
    end
  end

  describe "#ical_rule" do
    it "keeps the UTC UNTIL for a timed event" do
      expect(described_class.parse(lines).ical_rule(all_day: false)).to eq("FREQ=WEEKLY;UNTIL=20261210T045959Z;BYDAY=MO")
    end

    it "gives a DATE UNTIL for an all-day event (RFC 5545)" do
      expect(described_class.parse(lines).ical_rule(all_day: true)).to eq("FREQ=WEEKLY;UNTIL=20261209;BYDAY=MO")
    end
  end
end
