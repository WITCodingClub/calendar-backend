# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Calendars", type: :request do
  include ActiveJob::TestHelper

  let(:admin) { create(:user, :super_admin) }

  before do
    stub_request(:get, "https://api.github.com/repos/WITCodingClub/calendar/releases/latest")
      .to_return(status: 200, body: { tag_name: "v0.0.0" }.to_json)
    sign_in admin
  end

  describe "DELETE /admin/calendars/:id" do
    it "deletes a Google calendar with the Google job, one time" do
      calendar = create(:course_calendar)

      expect { delete admin_calendar_path(calendar) }
        .to have_enqueued_job(GoogleCalendarDeleteJob).with(calendar.external_calendar_id).exactly(:once)

      expect(CourseCalendar.exists?(calendar.id)).to be(false)
    end

    it "deletes a Microsoft calendar with the Microsoft job, and never with the Google job" do
      calendar = create(:course_calendar, :microsoft)

      expect { delete admin_calendar_path(calendar) }
        .to have_enqueued_job(MicrosoftGraphCalendarDeleteJob).with(calendar.oauth_credential_id, calendar.external_calendar_id)

      expect(GoogleCalendarDeleteJob).not_to have_been_enqueued
    end
  end
end
