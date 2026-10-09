# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ICS calendar feed university events", type: :request do
  let(:user) { create(:user) }
  let(:term) { create(:term, start_date: Date.new(2026, 9, 1), end_date: Date.new(2026, 12, 20)) }
  let(:course) { create(:course, term: term) }

  before do
    allow(CourseCalendars::SyncJob).to receive(:perform_later)
    create(:enrollment, user: user, course: course, term: term)
    create(:university_calendar_event, summary: "Registration Opens", category: "registration",
                                       start_time: Time.zone.local(2026, 10, 1, 9), end_time: Time.zone.local(2026, 10, 1, 10))
    create(:university_calendar_event, summary: "Career Fair", category: "campus_event",
                                       start_time: Time.zone.local(2026, 10, 2, 9), end_time: Time.zone.local(2026, 10, 2, 10))
  end

  def summaries
    get "/calendar/#{user.calendar_token}.ics"
    response.body.split("\r\n").grep(/\ASUMMARY:/)
  end

  it "leaves out a selected category that no longer syncs" do
    user.user_extension_config.update!(sync_university_events: true, university_event_categories: %w[registration campus_event])

    expect(summaries).to include("SUMMARY:Registration Opens")
    expect(summaries).not_to include("SUMMARY:Career Fair")
  end

  describe "colors" do
    before do
      user.user_extension_config.update!(sync_university_events: true, university_event_categories: %w[registration])
    end

    def color_lines
      get "/calendar/#{user.calendar_token}.ics"
      response.body.split("\r\n").grep(/COLOR/)
    end

    it "gives a university event Graphite while the user has not picked a color" do
      expect(color_lines).to contain_exactly("COLOR:#{GoogleCalendar::Colors::GRAPHITE}", "X-APPLE-CALENDAR-COLOR:#{GoogleCalendar::Colors::GRAPHITE}")
    end

    it "gives a university event the university wide color the user picked" do
      create(:calendar_preference, :uni_cal_global, user: user, color_id: "#1a2b3c")

      expect(color_lines).to contain_exactly("COLOR:#1a2b3c", "X-APPLE-CALENDAR-COLOR:#1a2b3c")
    end
  end
end
