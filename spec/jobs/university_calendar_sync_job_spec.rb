# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe UniversityCalendarSyncJob do
  include ActiveJob::TestHelper

  let(:ics_content) { Rails.root.join("spec/fixtures/files/university_calendar.ics").read }
  let(:ics_url) { UniversityCalendarIcsService::ICS_FEED_URL }

  before do
    stub_request(:get, ics_url)
      .to_return(status: 200, body: ics_content, headers: { "Content-Type" => "text/calendar" })
  end

  describe "#perform" do
    it "calls UniversityCalendarIcsService" do
      expect(UniversityCalendarIcsService).to receive(:call).and_call_original

      described_class.new.perform
    end

    it "creates university calendar events" do
      expect { described_class.new.perform }.to change(UniversityCalendarEvent, :count)
    end

    context "when holidays change" do
      let!(:user) do
        user = create(:user)
        oauth = create(:oauth_credential, user: user)
        create(:google_calendar, oauth_credential: oauth)
        user
      end

      it "triggers calendar sync for all users" do
        # First run creates holidays
        expect {
          described_class.new.perform
        }.to have_enqueued_job(GoogleCalendarSyncJob).with(user, force: true)
      end
    end

    context "when only non-holiday events change" do
      let!(:opted_in_user) do
        user = create(:user)
        oauth = create(:oauth_credential, user: user)
        create(:google_calendar, oauth_credential: oauth)
        create(:user_extension_config, user: user, sync_university_events: true)
        user
      end

      let!(:opted_out_user) do
        user = create(:user)
        oauth = create(:oauth_credential, user: user)
        create(:google_calendar, oauth_credential: oauth)
        create(:user_extension_config, user: user, sync_university_events: false)
        user
      end

      before do
        # Pre-populate holidays so holiday count doesn't change
        create(:university_calendar_event, :holiday, ics_uid: "event-thanksgiving@university.edu")
        create(:university_calendar_event, :holiday, ics_uid: "event-labor-day@university.edu")
      end

      it "only triggers sync for opted-in users when holidays dont change" do
        # Stub the service to report no holiday changes
        allow(UniversityCalendarIcsService).to receive(:call).and_return({
                                                                           created: 1,
                                                                           updated: 0,
                                                                           unchanged: 5,
                                                                           errors: []
                                                                         })

        # Run the job without performing enqueued jobs (which would make real HTTP calls)
        described_class.new.perform

        # Should have enqueued sync only for opted-in user (not opted-out user)
        # This verifies the job correctly filters to opted-in users when holidays don't change
        expect(GoogleCalendarSyncJob).to have_been_enqueued.with(opted_in_user, force: true)
        expect(GoogleCalendarSyncJob).not_to have_been_enqueued.with(opted_out_user, force: true)
      end
    end
  end

  describe "term date extraction" do
    let!(:term) { create(:term, year: 2025, season: :fall, start_date: nil, end_date: nil) }

    before do
      create(:university_calendar_event, :classes_begin,
             summary: "Fall 2025 Classes Begin",
             academic_term: "Fall",
             start_time: Date.new(2025, 8, 25).beginning_of_day)
      create(:university_calendar_event, :finals,
             summary: "Fall 2025 Final Exams",
             academic_term: "Fall",
             start_time: Date.new(2025, 12, 15).beginning_of_day,
             end_time: Date.new(2025, 12, 19).end_of_day)
    end

    it "updates term dates from university events" do
      # Stub the service to not change events
      allow(UniversityCalendarIcsService).to receive(:call).and_return({
                                                                         created: 0,
                                                                         updated: 0,
                                                                         unchanged: 0,
                                                                         errors: []
                                                                       })

      described_class.new.perform

      term.reload
      expect(term.start_date).to eq(Date.new(2025, 8, 25))
      expect(term.end_date).to eq(Date.new(2025, 12, 19))
    end
  end

  describe "queue configuration" do
    it "uses the low priority queue" do
      expect(described_class.new.queue_name).to eq("low")
    end
  end
end
