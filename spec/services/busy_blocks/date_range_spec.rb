# frozen_string_literal: true

require "rails_helper"

RSpec.describe BusyBlocks::DateRange do
  include ActiveSupport::Testing::TimeHelpers

  it "reads ISO dates, and gives a week from today when both are blank" do
    expect(described_class.parse("2026-10-05", "2026-10-09")).to eq([ Date.new(2026, 10, 5), Date.new(2026, 10, 9) ])

    travel_to(Date.new(2026, 10, 5)) do
      expect(described_class.parse(nil, "")).to eq([ Date.new(2026, 10, 5), Date.new(2026, 10, 11) ])
    end
  end

  it "refuses a date that is not YYYY-MM-DD, an end before the start, and a range over MAX_DAYS" do
    expect { described_class.parse("10/05/2026", nil) }
      .to raise_error(described_class::InvalidError, "start_date must be a date in YYYY-MM-DD format")
    expect { described_class.parse("2026-10-05", "2026-10-04") }
      .to raise_error(described_class::InvalidError, "end_date must not be before start_date")
    expect { described_class.parse("2026-10-05", (Date.new(2026, 10, 5) + BusyBlocks::MAX_DAYS).iso8601) }
      .to raise_error(described_class::InvalidError, "The range must be #{BusyBlocks::MAX_DAYS} days or fewer")
    expect(described_class.parse("2026-10-05", (Date.new(2026, 10, 4) + BusyBlocks::MAX_DAYS).iso8601).last)
      .to eq(Date.new(2026, 10, 4) + BusyBlocks::MAX_DAYS)
  end
end
