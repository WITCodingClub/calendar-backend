# frozen_string_literal: true

require "rails_helper"

RSpec.describe Hhmm do
  it "counts the minutes since midnight" do
    expect(described_class.minutes(945)).to eq(585)
    expect(described_class.minutes(1000) - described_class.minutes(945)).to eq(15)
    expect(described_class.hours(1330)).to eq(13.5)
  end

  it "formats a 24-hour and a 12-hour clock" do
    expect(described_class.format(905)).to eq("09:05")
    expect(described_class.format_12h(0)).to eq("12:00 AM")
    expect(described_class.format_12h(1200)).to eq("12:00 PM")
    expect(described_class.format_12h(1350)).to eq("1:50 PM")
    expect(described_class.format_12h(900, short: true)).to eq("9 AM")
    expect(described_class.format_12h(1330, short: true)).to eq("1:30 PM")
    expect(described_class.format_12h(2400, short: true)).to eq("12 AM")
  end

  it "reads a time of day from a text" do
    expect(described_class.parse("1315")).to eq(1315)
    expect(described_class.parse("800")).to eq(800)
    expect(described_class.parse("9:05")).to eq(905)
    expect(described_class.parse("1:15 PM")).to eq(1315)
    expect(described_class.parse("12:30 am")).to eq(30)
    expect(described_class.parse(930)).to eq(930)
  end

  it "answers nil for a text that is not a time of day" do
    expect([ "", "abc", "2400", "1260", "25:00", "9", "12345" ].map { |text| described_class.parse(text) }).to all(be_nil)
  end

  it "converts between a time and HHMM" do
    time = described_class.on(Date.new(2027, 1, 12), 1350)

    expect(time).to eq(Time.zone.local(2027, 1, 12, 13, 50))
    expect(described_class.from_time(time)).to eq(1350)
  end
end
