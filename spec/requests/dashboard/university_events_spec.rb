# frozen_string_literal: true

require "rails_helper"

# Issue #797: the university calendar, read-only, for any signed-in user.
RSpec.describe "Dashboard::UniversityEvents", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  # A method, not a let: one example makes several requests.
  def page = Nokogiri::HTML(response.body)
  let(:zone) { Time.zone }

  around { |example| travel_to(zone.local(2026, 11, 6, 12)) { example.run } }

  before do
    create(:university_calendar_event, summary: "Thanksgiving Break", category: "holiday", all_day: true,
                                       start_time: zone.local(2026, 11, 25), end_time: zone.local(2026, 11, 28))
    create(:university_calendar_event, summary: "Career Fair", category: "campus_event", location: "Flanagan Campus Center",
                                       description: "<p>Bring a resume.</p>",
                                       start_time: zone.local(2026, 11, 10, 14), end_time: zone.local(2026, 11, 10, 16))
    create(:university_calendar_event, summary: "Columbus Day", category: "holiday", all_day: true,
                                       start_time: zone.local(2026, 10, 12), end_time: zone.local(2026, 10, 13))
    sign_in user
  end

  def summaries = page.css("#events > div p.font-medium").map(&:text)

  it "lists upcoming events, soonest first" do
    get dashboard_university_events_path

    expect(response).to have_http_status(:ok)
    expect(summaries).to eq([ "Career Fair", "Thanksgiving Break" ])
    expect(page.at_css("#events").text).to include("Tue, Nov 10, 2:00 PM – 4:00 PM · Flanagan Campus Center",
                                                   "Wed, Nov 25 – Fri, Nov 27", "Bring a resume.")
    expect(response.body).not_to include("<p>Bring a resume.</p>")
  end

  it "lists past events with past=1, newest first" do
    get dashboard_university_events_path, params: { past: "1" }

    expect(summaries).to eq([ "Columbus Day" ])
  end

  it "filters by category and search words" do
    get dashboard_university_events_path, params: { category: "holiday" }
    expect(summaries).to eq([ "Thanksgiving Break" ])

    get dashboard_university_events_path, params: { q: "flanagan" }
    expect(summaries).to eq([ "Career Fair" ])
  end

  it "ignores an unknown category" do
    get dashboard_university_events_path, params: { category: "parties" }

    expect(summaries).to eq([ "Career Fair", "Thanksgiving Break" ])
  end

  it "shows an empty state when nothing matches" do
    get dashboard_university_events_path, params: { q: "nothing like this" }

    expect(page.at_css("[data-empty-state]").text).to include("No upcoming events match.")
  end
end
