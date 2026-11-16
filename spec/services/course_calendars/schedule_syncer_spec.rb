# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseCalendars::ScheduleSyncer do
  subject(:syncer) { described_class.new(user) }

  let(:user)    { create(:user, calendar_needs_sync: true, last_calendar_sync_at: nil) }
  let(:term)    { create(:term) }
  let(:course)  { create(:course, term: term) }
  let(:stats)   { { created: 1, updated: 2, skipped: 0 } }
  let(:google)  { instance_double(GoogleCalendar::Provider, course_calendar: nil) }
  let(:microsoft) { instance_double(MicrosoftGraph::CalendarProvider, course_calendar: nil) }
  let(:services)  { [ google, microsoft ] }

  before do
    allow(CourseCalendars::Providers).to receive(:services_for).with(user).and_return(services)
    services.each do |service|
      allow(service).to receive_messages(update_calendar_events: stats, update_specific_events: stats)
    end
  end

  describe "#sync_schedule" do
    let!(:enrollment)   { create(:enrollment, user: user, course: course) }
    let!(:meeting_time) { create(:course_meeting_time, course: course) }
    let!(:final_exam)   { create(:final_exam, course: course, term: term, exam_date: 1.week.from_now.to_date) }
    let!(:holiday) do
      create(:university_calendar_event, category: "holiday", start_time: 1.week.from_now, end_time: 1.week.from_now + 1.day)
    end

    it "sends the course, final, and university events to each provider in order" do
      syncer.sync_schedule(force: true)

      expect(google).to have_received(:update_calendar_events).with(
        contain_exactly(
          have_attributes(source: meeting_time), have_attributes(source: final_exam), have_attributes(source: holiday)
        ),
        force: true
      ).ordered
      expect(microsoft).to have_received(:update_calendar_events).with(an_instance_of(Array), force: true).ordered
    end

    it "adds up the stats of the providers" do
      expect(syncer.sync_schedule).to eq(created: 2, updated: 4, skipped: 0)
    end

    it "records the sync and clears the needs-sync flag" do
      syncer.sync_schedule

      expect(user.reload).to have_attributes(calendar_needs_sync: false, last_calendar_sync_at: be_present)
    end

    it "does not record a sync that changed nothing" do
      services.each { |service| allow(service).to receive(:update_calendar_events).and_return(created: 0, updated: 0, skipped: 0) }

      syncer.sync_schedule

      expect(user.reload).to have_attributes(calendar_needs_sync: true, last_calendar_sync_at: nil)
    end

    it "starts the historical backfill on a forced sync" do
      expect { syncer.sync_schedule(force: true) }
        .to have_enqueued_job(CourseCalendars::HistoricalSyncJob).with(user, force: true)
    end

    it "does not start the backfill on a quick sync" do
      expect { syncer.sync_schedule(force: false) }.not_to have_enqueued_job(CourseCalendars::HistoricalSyncJob)
    end

    it "does not start the backfill when no provider ran" do
      allow(CourseCalendars::Providers).to receive(:services_for).with(user).and_return([])

      expect { syncer.sync_schedule(force: true) }.not_to have_enqueued_job(CourseCalendars::HistoricalSyncJob)
    end

    it "prunes unwanted university events, publishes missing friend meetings, and removes declined friends" do
      pruner    = instance_double(CourseCalendars::UniversityEventPruner, call: 0)
      publisher = instance_double(FriendMeetings::Publisher, publish_missing: nil, remove_declined: nil)
      allow(CourseCalendars::UniversityEventPruner).to receive(:new).with(user).and_return(pruner)
      allow(FriendMeetings::Publisher).to receive(:new).with(user, services: services).and_return(publisher)

      syncer.sync_schedule

      expect(pruner).to have_received(:call)
      expect(publisher).to have_received(:publish_missing)
      expect(publisher).to have_received(:remove_declined)
    end

    context "when one provider fails" do
      let(:error) { Signet::AuthorizationError.new("token revoked") }

      before do
        allow(google).to receive(:update_calendar_events).and_raise(error)
        allow(Rails.error).to receive(:report)
      end

      it "still syncs the other provider and returns its stats" do
        expect(syncer.sync_schedule).to eq(stats)
        expect(microsoft).to have_received(:update_calendar_events)
      end

      it "reports the failure with the user and the provider" do
        syncer.sync_schedule

        expect(Rails.error).to have_received(:report)
          .with(error, handled: true, context: { user_id: user.id, provider: google.class.name })
      end

      it "still prunes, publishes friend meetings, and records the sync" do
        pruner    = instance_double(CourseCalendars::UniversityEventPruner, call: 0)
        publisher = instance_double(FriendMeetings::Publisher, publish_missing: nil, remove_declined: nil)
        allow(CourseCalendars::UniversityEventPruner).to receive(:new).with(user).and_return(pruner)
        allow(FriendMeetings::Publisher).to receive(:new).with(user, services: services).and_return(publisher)

        syncer.sync_schedule

        expect(pruner).to have_received(:call)
        expect(publisher).to have_received(:publish_missing)
        expect(user.reload).to have_attributes(calendar_needs_sync: false, last_calendar_sync_at: be_present)
      end
    end

    context "when one provider hits a rate limit and the other provider works" do
      before do
        allow(google).to receive(:update_calendar_events).and_raise(CourseCalendars::RateLimitError, "rateLimitExceeded")
        allow(Rails.error).to receive(:report)
      end

      it "raises the rate limit, so the job retries, and does not record a sync" do
        expect { syncer.sync_schedule }.to raise_error(CourseCalendars::RateLimitError)

        expect(microsoft).to have_received(:update_calendar_events)
        expect(Rails.error).not_to have_received(:report)
        expect(user.reload).to have_attributes(calendar_needs_sync: true, last_calendar_sync_at: nil)
      end
    end

    context "when every provider fails" do
      before do
        allow(google).to receive(:update_calendar_events).and_raise(Signet::AuthorizationError, "token revoked")
        allow(microsoft).to receive(:update_calendar_events).and_raise(MicrosoftGraph::AuthError, "token revoked")
        allow(Rails.error).to receive(:report)
      end

      it "raises the first error, so the job fails" do
        expect { syncer.sync_schedule }.to raise_error(Signet::AuthorizationError)
      end

      it "reports the other failures as handled, and leaves the raised one to the executor" do
        expect { syncer.sync_schedule }.to raise_error(Signet::AuthorizationError)

        expect(Rails.error).to have_received(:report).once
        expect(Rails.error).to have_received(:report)
          .with(an_instance_of(MicrosoftGraph::AuthError), handled: true,
                context: { user_id: user.id, provider: microsoft.class.name })
      end

      it "does not record a sync" do
        expect { syncer.sync_schedule }.to raise_error(Signet::AuthorizationError)

        expect(user.reload).to have_attributes(calendar_needs_sync: true, last_calendar_sync_at: nil)
      end
    end

    it "builds the events with the injected event builder" do
      event  = instance_double(CourseCalendars::Event)
      events = instance_double(CourseCalendars::EventBuilder, class_events: [ event ], final_exam_events: [], university_events: [])

      described_class.new(user, events: events).sync_schedule

      expect(google).to have_received(:update_calendar_events).with([ event ], force: false)
    end
  end

  describe "isolation in the historical sync" do
    before do
      allow(google).to receive(:update_specific_events).and_raise(Signet::AuthorizationError, "token revoked")
      allow(Rails.error).to receive(:report)
      create(:enrollment, user: user, course: course)
      create(:final_exam, course: course, term: term, exam_date: 1.week.ago.to_date)
    end

    it "syncs the other provider" do
      expect(syncer.sync_historical).to eq(stats)
      expect(microsoft).to have_received(:update_specific_events)
    end

    it "raises when every provider fails" do
      allow(microsoft).to receive(:update_specific_events).and_raise(MicrosoftGraph::AuthError, "token revoked")

      expect { syncer.sync_historical }.to raise_error(Signet::AuthorizationError)
    end
  end

  describe "#sync_historical" do
    it "sends past finals and university events as specific events" do
      create(:enrollment, user: user, course: course)
      past_final = create(:final_exam, course: course, term: term, exam_date: 1.week.ago.to_date)

      syncer.sync_historical(force: true)

      expect(google).to have_received(:update_specific_events)
        .with([ have_attributes(source: past_final) ], force: true)
    end

    it "returns nil and calls no provider when there is nothing in the past" do
      expect(syncer.sync_historical).to be_nil
      expect(google).not_to have_received(:update_specific_events)
    end
  end
end
