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
          a_hash_including(meeting_time_id: meeting_time.id),
          a_hash_including(final_exam_id: final_exam.id),
          a_hash_including(university_calendar_event_id: holiday.id)
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

    it "builds the events with the injected event builder" do
      events = instance_double(CourseCalendars::EventBuilder, preload_holidays!: nil, finals_events: [], university_events: [])
      allow(events).to receive(:course_events).and_return([ { summary: "X" } ])

      described_class.new(user, events: events).sync_schedule

      expect(events).to have_received(:course_events).with(anything, prefer_valid_locations: true)
      expect(google).to have_received(:update_calendar_events).with([ { summary: "X" } ], force: false)
    end
  end

  describe "#sync_enrollments" do
    it "sends only the events of the given enrollments as specific events" do
      enrollment = create(:enrollment, user: user, course: course)
      meeting_time = create(:course_meeting_time, course: course)
      other_course = create(:course, term: term)
      create(:enrollment, user: user, course: other_course)
      create(:course_meeting_time, course: other_course)

      syncer.sync_enrollments([ enrollment.id ])

      expect(google).to have_received(:update_specific_events)
        .with([ a_hash_including(meeting_time_id: meeting_time.id) ], force: false)
      expect(user.reload.calendar_needs_sync).to be(false)
    end
  end

  describe "#sync_meeting_time" do
    it "sends the one meeting time and records only the sync time" do
      meeting_time = create(:course_meeting_time, course: course)

      expect(syncer.sync_meeting_time(meeting_time.id)).to eq(created: 2, updated: 4, skipped: 0)
      expect(google).to have_received(:update_specific_events)
        .with([ a_hash_including(meeting_time_id: meeting_time.id) ], force: true)
      expect(user.reload).to have_attributes(calendar_needs_sync: true, last_calendar_sync_at: be_present)
    end

    it "returns nil for an unknown meeting time" do
      expect(syncer.sync_meeting_time(0)).to be_nil
      expect(google).not_to have_received(:update_specific_events)
    end
  end

  describe "#sync_final_exam" do
    it "sends the one final exam" do
      final_exam = create(:final_exam, course: course, term: term)

      syncer.sync_final_exam(final_exam.id, force: false)

      expect(google).to have_received(:update_specific_events)
        .with([ a_hash_including(final_exam_id: final_exam.id) ], force: false)
    end

    it "returns nil for an unknown final exam" do
      expect(syncer.sync_final_exam(0)).to be_nil
    end
  end

  describe "#sync_historical" do
    it "sends past finals and university events as specific events" do
      create(:enrollment, user: user, course: course)
      past_final = create(:final_exam, course: course, term: term, exam_date: 1.week.ago.to_date)

      syncer.sync_historical(force: true)

      expect(google).to have_received(:update_specific_events)
        .with([ a_hash_including(final_exam_id: past_final.id) ], force: true)
    end

    it "returns nil and calls no provider when there is nothing in the past" do
      expect(syncer.sync_historical).to be_nil
      expect(google).not_to have_received(:update_specific_events)
    end
  end
end
