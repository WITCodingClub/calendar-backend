# frozen_string_literal: true

require "rails_helper"

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

  let(:google_service) { instance_double(Google::Apis::CalendarV3::CalendarService) }

  before do
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
    allow_any_instance_of(GoogleCalendarService).to receive(:user_calendar_service).and_return(google_service) # rubocop:disable RSpec/AnyInstance
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
    it "prunes unwanted past university events" do
      config.update!(sync_university_events: false)
      allow_any_instance_of(GoogleCalendarService).to receive(:update_calendar_events).and_return( # rubocop:disable RSpec/AnyInstance
        { created: 0, updated: 0, skipped: 0 }
      )

      user.sync_course_schedule(force: false)

      expect(CalendarEvent.exists?(registration_gcal_event.id)).to be(false)
    end
  end
end
