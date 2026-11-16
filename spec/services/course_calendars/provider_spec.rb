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

    before { create(:oauth_credential, user: user) }

    it "starts one forced sync for a calendar it made" do
      allow(service).to receive(:create_or_get_course_calendar) do
        create(:course_calendar, oauth_credential: user.google_credential, external_calendar_id: "new-calendar")
        "new-calendar"
      end

      expect { expect(service.ensure_course_calendar).to eq("new-calendar") }
        .to have_enqueued_job(CourseCalendars::SyncJob).with(user, force: true).exactly(:once)
    end

    it "starts no sync for a calendar that was there" do
      calendar = create(:course_calendar, oauth_credential: user.google_credential)
      allow(service).to receive(:create_or_get_course_calendar).and_return(calendar.external_calendar_id)

      expect { service.ensure_course_calendar }.not_to have_enqueued_job(CourseCalendars::SyncJob)
    end

    it "forces the reconnect sync of a Microsoft calendar that was there", :microsoft_graph do
      credential = create(:oauth_credential, :microsoft, user: user)
      calendar   = create(:course_calendar, :microsoft, oauth_credential: credential)
      Flipper.enable_actor(FeatureFlags::MICROSOFT_GRAPH_CALENDAR, user)
      microsoft = MicrosoftGraph::CalendarProvider.new(user, credential: credential)
      allow(microsoft).to receive(:create_or_get_course_calendar).and_return(calendar.external_calendar_id)

      expect { microsoft.ensure_course_calendar(always_sync: true) }
        .to have_enqueued_job(CourseCalendars::SyncJob).with(user, force: true).exactly(:once)
    ensure
      Flipper.disable(FeatureFlags::MICROSOFT_GRAPH_CALENDAR)
    end

    it "starts a sync without force for a Google calendar that was there, when asked to" do
      calendar = create(:course_calendar, oauth_credential: user.google_credential)
      allow(service).to receive(:create_or_get_course_calendar).and_return(calendar.external_calendar_id)

      expect { service.ensure_course_calendar(always_sync: true) }
        .to have_enqueued_job(CourseCalendars::SyncJob).with(user, force: false).exactly(:once)
    end
  end
end
