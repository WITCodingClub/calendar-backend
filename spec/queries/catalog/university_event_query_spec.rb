# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::UniversityEventQuery do
  include ActiveSupport::Testing::TimeHelpers

  let(:zone) { Time.zone }
  let!(:fair) { create(:university_calendar_event, summary: "Career Fair", category: "campus_event", location: "Flanagan", start_time: zone.local(2026, 11, 10, 14), end_time: zone.local(2026, 11, 10, 16)) }
  let!(:break_event) { create(:university_calendar_event, summary: "Thanksgiving Break", category: "holiday", start_time: zone.local(2026, 11, 25), end_time: zone.local(2026, 11, 28)) }
  let!(:old) { create(:university_calendar_event, summary: "Columbus Day", category: "holiday", start_time: zone.local(2026, 10, 12), end_time: zone.local(2026, 10, 13)) }

  around { |example| travel_to(zone.local(2026, 11, 6, 12)) { example.run } }

  def call(**args) = described_class.new.call(**args).to_a

  it "lists upcoming events soonest first" do
    expect(call).to eq([ fair, break_event ])
  end

  it "lists past events newest first" do
    expect(call(past: true)).to eq([ old ])
  end

  it "filters by category and ignores an unknown one" do
    expect(call(category: "holiday")).to eq([ break_event ])
    expect(call(category: "parties")).to eq([ fair, break_event ])
  end

  it "matches the summary or the location" do
    expect(call(q: "flanagan")).to eq([ fair ])
    expect(call(q: "thanksgiving break")).to eq([ break_event ])
  end
end
