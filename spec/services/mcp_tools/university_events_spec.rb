# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::UniversityEvents do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  around { |example| travel_to(Time.zone.local(2026, 10, 14, 12)) { example.run } }

  def call(**arguments) = described_class.call(server_context: { user: user }, **arguments)

  def event(summary, on:, category: "holiday")
    create(:university_calendar_event, summary: summary, category: category,
                                       start_time: on.in_time_zone.change(hour: 9), end_time: on.in_time_zone.change(hour: 10))
  end

  it "lists upcoming events without dates" do
    event("Past", on: Date.new(2026, 10, 1))
    event("Thanksgiving", on: Date.new(2026, 11, 26))

    expect(call.structured_content[:events].pluck(:summary)).to eq([ "Thanksgiving" ])
  end

  it "filters by date range and category" do
    event("Holiday", on: Date.new(2026, 11, 11))
    event("Deadline", on: Date.new(2026, 11, 12), category: "deadline")
    event("Later", on: Date.new(2027, 1, 5))

    result = call(start_date: "2026-11-01", end_date: "2026-11-30", categories: [ "deadline" ])

    expect(result.structured_content[:events].pluck(:summary)).to eq([ "Deadline" ])
  end

  it "uses today as the start when only an end date is given" do
    event("Past", on: Date.new(2026, 10, 1))
    event("Soon", on: Date.new(2026, 10, 20))

    expect(call(end_date: "2026-10-31").structured_content[:events].pluck(:summary)).to eq([ "Soon" ])
  end

  it "refuses an end date before the start date" do
    expect(call(start_date: "2026-11-01", end_date: "2026-10-01").error?).to be(true)
  end
end
