# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseCalendars::Provider do
  describe ".provider_name" do
    it "is the stored name of each subclass" do
      expect(GoogleCalendar::Provider.provider_name).to eq("google")
      expect(MicrosoftGraph::CalendarProvider.provider_name).to eq("microsoft")
    end
  end

  describe "#ensure_course_calendar" do
    let(:user)    { create(:user) }
    let(:service) { GoogleCalendar::Provider.new(user) }
    let(:google_calendar_json) do
      { status: 200, headers: { "Content-Type" => "application/json" },
        body: { id: "new-calendar", summary: "WIT Courses", timeZone: "America/New_York" }.to_json }
    end

    # The Google calendar, ACL, and calendar list calls all answer with the calendar.
    before do
      create(:oauth_credential, user: user, token_expires_at: 1.hour.from_now)
      stub_google_service_account
      stub_request(:any, /googleapis\.com/).to_return(google_calendar_json)
    end

    it "starts one forced sync for a calendar it made" do
      expect { expect(service.ensure_course_calendar).to eq("new-calendar") }
        .to have_enqueued_job(CourseCalendars::SyncJob).with(user, force: true).exactly(:once)
    end

    it "starts no sync for a calendar that was there" do
      create(:course_calendar, oauth_credential: user.google_credential)

      expect { service.ensure_course_calendar }.not_to have_enqueued_job(CourseCalendars::SyncJob)
    end

    it "forces the reconnect sync of a Microsoft calendar that was there", :microsoft_graph do
      credential = create(:oauth_credential, :microsoft, user: user, token_expires_at: 1.hour.from_now)
      create(:course_calendar, :microsoft, oauth_credential: credential, external_calendar_id: "AAMkSyntheticCalendar1")
      stub_request(:get, "#{MicrosoftGraphHelpers::GRAPH_URL}/me/calendars/AAMkSyntheticCalendar1").with(query: hash_including({}))
        .to_return(graph_json_response("calendar_found"))
      Flipper.enable_actor(FeatureFlags::MICROSOFT_GRAPH_CALENDAR, user)
      microsoft = MicrosoftGraph::CalendarProvider.new(user, credential: credential)

      expect { microsoft.ensure_course_calendar(always_sync: true) }
        .to have_enqueued_job(CourseCalendars::SyncJob).with(user, force: true).exactly(:once)
    ensure
      Flipper.disable(FeatureFlags::MICROSOFT_GRAPH_CALENDAR)
    end

    it "starts a sync without force for a Google calendar that was there, when asked to" do
      create(:course_calendar, oauth_credential: user.google_credential)

      expect { service.ensure_course_calendar(always_sync: true) }
        .to have_enqueued_job(CourseCalendars::SyncJob).with(user, force: false).exactly(:once)
    end
  end
end
