# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendshipExpiryTime do
  let(:new_york) { ActiveSupport::TimeZone["America/New_York"] }

  describe ".parse" do
    it "reads a date with no time as the end of that day in New York" do
      expect(described_class.parse("2026-12-01")).to eq(new_york.local(2026, 12, 1, 23, 59, 59))
    end

    it "uses the summer offset for a date in daylight saving time" do
      expect(described_class.parse("2026-07-01").utc_offset).to eq(-4.hours)
      expect(described_class.parse("2026-12-01").utc_offset).to eq(-5.hours)
    end

    it "keeps a time with a UTC offset as that exact moment" do
      expect(described_class.parse("2026-12-01T17:00:00Z")).to eq(Time.utc(2026, 12, 1, 17))
      expect(described_class.parse("2026-12-01T12:00:00-05:00")).to eq(Time.utc(2026, 12, 1, 17))
      expect(described_class.parse("2026-12-01T12:00:00-0500")).to eq(Time.utc(2026, 12, 1, 17))
    end

    it "returns the time in the app zone" do
      expect(described_class.parse("2026-12-01T17:00:00Z").time_zone).to eq(Time.zone)
    end

    it "refuses a time with no UTC offset" do
      expect(described_class.parse("2026-12-01T12:00:00")).to be_nil
    end

    it "refuses values that are not ISO 8601" do
      expect(described_class.parse("next tuesday")).to be_nil
      expect(described_class.parse("2026-13-45")).to be_nil
      expect(described_class.parse("")).to be_nil
      expect(described_class.parse(nil)).to be_nil
    end
  end
end
