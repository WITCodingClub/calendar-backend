# frozen_string_literal: true

require "rails_helper"

# Integration tests through User. The CourseCalendars classes have their own
# specs for the details: ScheduleSyncer, EventBuilder, RecurrenceBuilder, and
# UniversityEventPruner.
RSpec.describe CourseScheduleSyncable, type: :model do
  let(:user)       { create(:user) }
  let(:credential) { create(:oauth_credential, user: user) }
  let(:calendar)   { create(:course_calendar, oauth_credential: credential, external_calendar_id: "cal_123") }
  let(:config) { user.user_extension_config }

  def university_event(summary:, category:, start_time:)
    create(:university_calendar_event,
           summary: summary, category: category, all_day: true,
           start_time: start_time, end_time: start_time + 1.day)
  end

  let(:past_holiday) do
    university_event(summary: "Fall Break", category: "holiday", start_time: 2.months.ago)
  end
  let(:past_registration) do
    university_event(summary: "Registration Opens", category: "registration", start_time: 2.months.ago)
  end

  let!(:holiday_event) do
    create(:calendar_event, :for_university_event, course_calendar: calendar,
           external_event_id: "gcal_holiday", university_calendar_event: past_holiday,
           end_time: past_holiday.end_time)
  end
  let!(:registration_gcal_event) do
    create(:calendar_event, :for_university_event, course_calendar: calendar,
           external_event_id: "gcal_registration", university_calendar_event: past_registration,
           end_time: past_registration.end_time)
  end

  let(:google_service)  { instance_double(Google::Apis::CalendarV3::CalendarService) }
  let(:google_provider) { GoogleCalendar::Provider.new(user) }

  before do
    allow(CourseCalendars::SyncJob).to receive(:perform_later)
    allow(GoogleCalendar::Provider).to receive(:new).and_call_original
    allow(GoogleCalendar::Provider).to receive(:new).with(user).and_return(google_provider)
    allow(google_provider).to receive(:user_calendar_service).and_return(google_service)
    allow(google_service).to receive(:delete_event)
    config.update!(sync_university_events: true, university_event_categories: %w[registration])
  end

  describe "#prune_unwanted_university_events" do
    it "keeps past events that the user still wants" do
      expect(user.prune_unwanted_university_events).to eq(0)
      expect(google_service).not_to have_received(:delete_event)
    end

    it "deletes a past event after the user turns off university event sync" do
      config.update!(sync_university_events: false)

      expect(user.prune_unwanted_university_events).to eq(1)
      expect(google_service).to have_received(:delete_event).with("cal_123", "gcal_registration")
      expect(CalendarEvent.exists?(registration_gcal_event.id)).to be(false)
    end

    it "keeps a friend meeting row and puts back a meeting that is missing from the calendar" do
      tracked = create(:calendar_event, :for_friend_meeting, course_calendar: calendar,
                                                             external_event_id: "gcal_meeting", end_time: 1.week.from_now)
      missing = create(:friend_meeting, user: user, destinations: %w[google])
      allow(google_service).to receive(:insert_event)
        .and_return(Google::Apis::CalendarV3::Event.new(id: "gcal_missing_meeting"))
      tracked.friend_meeting.update!(user: user)

      user.sync_course_schedule(force: false)

      expect(CalendarEvent.exists?(tracked.id)).to be(true)
      expect(google_service).not_to have_received(:delete_event).with("cal_123", "gcal_meeting")
      expect(missing.calendar_events.sole).to have_attributes(external_event_id: "gcal_missing_meeting", calendar_id: calendar.id)
    end

    it "deletes a past event after the user unselects its category" do
      config.update!(university_event_categories: %w[deadline])

      expect(user.prune_unwanted_university_events).to eq(1)
      expect(google_service).to have_received(:delete_event).with("cal_123", "gcal_registration")
    end

    it "deletes a past event in a category that no longer syncs" do
      campus_event = university_event(summary: "Career Fair", category: "campus_event", start_time: 2.months.ago)
      create(:calendar_event, :for_university_event, course_calendar: calendar,
             external_event_id: "gcal_campus", university_calendar_event: campus_event, end_time: campus_event.end_time)
      config.update!(university_event_categories: %w[registration campus_event])

      expect(user.prune_unwanted_university_events).to eq(1)
      expect(google_service).to have_received(:delete_event).with("cal_123", "gcal_campus")
    end

    it "keeps past holidays when university event sync is off" do
      config.update!(sync_university_events: false)
      user.prune_unwanted_university_events

      expect(CalendarEvent.exists?(holiday_event.id)).to be(true)
      expect(google_service).not_to have_received(:delete_event).with("cal_123", "gcal_holiday")
    end

    it "returns zero when the user has no calendar" do
      other_user = create(:user)

      expect(other_user.prune_unwanted_university_events).to eq(0)
    end
  end

  describe "#build_university_events_for_sync" do
    it "leaves out a selected category that no longer syncs" do
      registration = university_event(summary: "Registration Opens", category: "registration", start_time: 1.week.from_now)
      university_event(summary: "Career Fair", category: "campus_event", start_time: 1.week.from_now)
      config.update!(university_event_categories: %w[registration campus_event])

      ids = user.build_university_events_for_sync.pluck(:university_calendar_event_id)

      expect(ids).to contain_exactly(registration.id)
    end
  end

  describe "#sync_course_schedule" do
    before do
      allow(google_provider).to receive(:update_calendar_events).and_return(created: 1, updated: 0, skipped: 0)
    end

    it "prunes unwanted past university events" do
      config.update!(sync_university_events: false)

      user.sync_course_schedule(force: false)

      expect(CalendarEvent.exists?(registration_gcal_event.id)).to be(false)
    end

    it "sends the course events to Google and records the sync" do
      course = create(:course)
      create(:enrollment, user: user, course: course)
      meeting_time = create(:course_meeting_time, course: course)

      expect(user.sync_course_schedule(force: false)).to eq(created: 1, updated: 0, skipped: 0)

      expect(google_provider).to have_received(:update_calendar_events)
        .with(including(a_hash_including(meeting_time_id: meeting_time.id)), force: false)
      expect(user.reload.calendar_needs_sync).to be(false)
    end

    it "queues the historical backfill on a force sync" do
      expect { user.force_sync }.to have_enqueued_job(CourseCalendars::HistoricalSyncJob).with(user, force: true)
    end

    it "does not queue the backfill on a quick sync" do
      expect { user.quick_sync }.not_to have_enqueued_job(CourseCalendars::HistoricalSyncJob)
    end
  end

  describe "#sync_historical_events" do
    it "sends past finals to Google as specific events" do
      course = create(:course)
      create(:enrollment, user: user, course: course)
      final_exam = create(:final_exam, course: course, term: course.term, exam_date: 1.week.ago.to_date)
      allow(google_provider).to receive(:update_specific_events).and_return(created: 1, updated: 0, skipped: 0)

      user.sync_historical_events(force: true)

      expect(google_provider).to have_received(:update_specific_events)
        .with(including(a_hash_including(final_exam_id: final_exam.id)), force: true)
    end
  end

  describe "memoized lookups" do
    it "keeps the final exam dates for the life of the user object" do
      course = create(:course)
      create(:final_exam, course: course, term: course.term, exam_date: Date.new(2026, 12, 10))
      allow(FinalExam).to receive(:where).and_call_original

      2.times { user.final_exam_date_for_course(course.id) }

      expect(FinalExam).to have_received(:where).once
    end
  end

  describe "helper delegators" do
    it "answers the date and location helpers through the CourseCalendars builders" do
      meeting_time = create(:course_meeting_time, day_of_week: :monday)

      expect(user.find_first_meeting_date(meeting_time)).to eq(Date.new(2026, 9, 14))
      expect(user.parse_time(Date.new(2026, 9, 14), 900)).to eq(Time.zone.local(2026, 9, 14, 9, 0))
      expect(user.tbd_room?(build(:room, number: "0"))).to be(true)
      expect(user.wanted_university_event_ids([ past_holiday.id ])).to eq([ past_holiday.id ])
    end
  end
end
