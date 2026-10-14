# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin university calendar backfill", type: :request do
  before do
    stub_request(:get, "https://api.github.com/repos/WITCodingClub/calendar/releases/latest")
      .to_return(status: 200, body: { tag_name: "v0.0.0" }.to_json)
    sign_in create(:user, :super_admin)
  end

  it "queues a backfill for a valid range" do
    expect { post backfill_admin_university_calendar_events_path, params: { start_date: "2026-01-01", end_date: "2026-01-31" } }
      .to have_enqueued_job(UniversityCalendar::BackfillJob).with("2026-01-01", "2026-01-31")
  end

  it "redirects with an alert when the dates are missing" do
    post backfill_admin_university_calendar_events_path

    expect(response).to redirect_to(admin_university_calendar_events_path)
    expect(flash[:alert]).to eq("Invalid date format.")
  end

  it "redirects with an alert when a date is an array" do
    post backfill_admin_university_calendar_events_path, params: { start_date: [ "x" ], end_date: [ "y" ] }

    expect(flash[:alert]).to eq("Invalid date format.")
  end
end
