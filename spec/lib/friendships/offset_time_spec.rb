# frozen_string_literal: true

require "rails_helper"

RSpec.describe Friendships::OffsetTime do
  it "reads a time with a UTC offset in the app zone" do
    time = described_class.parse("2026-12-01T12:00:00-05:00")

    expect(time).to eq(Time.utc(2026, 12, 1, 17))
    expect(time.time_zone).to eq(Time.zone)
  end

  it "refuses a time with no offset, a date, and text" do
    expect([ "2026-12-01T12:00:00", "2026-12-01", "soon", nil ].map { |value| described_class.parse(value) })
      .to all(be_nil)
  end
end
