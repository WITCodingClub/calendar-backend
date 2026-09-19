# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ICS calendar feed university events", type: :request do
  let(:user) { create(:user) }
  let(:term) { create(:term, start_date: Date.new(2026, 9, 1), end_date: Date.new(2026, 12, 20)) }
  let(:course) { create(:course, term: term) }

  before do
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
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
end
