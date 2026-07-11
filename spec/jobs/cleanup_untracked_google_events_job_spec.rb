# frozen_string_literal: true

require "rails_helper"

RSpec.describe CleanupUntrackedGoogleEventsJob do
  let(:user) { User.create!(email: "student@wit.edu", password: "password123") }
  let(:credential) do
    user.oauth_credentials.create!(
      provider: "google", uid: "google-uid", email: user.email, access_token: "token"
    )
  end
  let(:calendar) { credential.create_google_calendar!(google_calendar_id: "cal_123") }

  let(:term) { Term.create!(uid: 202710, season: :fall, year: 2026) }
  let(:course) do
    Course.create!(
      crn: 12345, term: term, title: "Data Structures", subject: "COMP",
      course_number: 2000, section_number: "01", schedule_type: "LEC",
      start_date: Date.new(2026, 9, 8), end_date: Date.new(2026, 12, 15)
    )
  end
  let(:meeting_time) do
    Course::MeetingTime.create!(
      course: course,
      start_date: Time.zone.local(2026, 9, 8),
      end_date: Time.zone.local(2026, 12, 15, 23, 59, 59),
      begin_time: 1300, end_time: 1445,
      day_of_week: :monday,
      meeting_schedule_type: :lecture, meeting_type: :class_meeting
    )
  end

  let!(:tracked_event) do
    calendar.google_calendar_events.create!(google_event_id: "tracked_1", meeting_time: meeting_time)
  end

  let(:fake_service) { instance_double(Google::Apis::CalendarV3::CalendarService) }
  let(:job) { described_class.new }

  def gcal_event(id:, status: "confirmed", summary: "Data Structures", recurring_event_id: nil)
    instance_double(
      Google::Apis::CalendarV3::Event,
      id: id, status: status, summary: summary, recurring_event_id: recurring_event_id
    )
  end

  let(:listed_events) do
    [
      gcal_event(id: "tracked_1"),
      gcal_event(id: "orphan_1"),
      gcal_event(id: "cancelled_1", status: "cancelled"),
      gcal_event(id: "tracked_1_20260914", recurring_event_id: "tracked_1")
    ]
  end

  before do
    allow(job).to receive(:calendar_service).and_return(fake_service)
    allow(fake_service).to receive(:list_events).and_return(
      instance_double(Google::Apis::CalendarV3::Events, items: listed_events, next_page_token: nil)
    )
    job.rate_limit_config = GoogleApiRateLimiter::RateLimitConfig.new.tap { |c| c.batch_throttle_delay = 0 }
  end

  it "deletes only untracked events, keeping tracked events and edited instances of tracked series" do
    expect(fake_service).to receive(:delete_event).with("cal_123", "orphan_1")

    result = job.perform(calendar.id)

    expect(result[:deleted]).to eq(1)
    expect(result[:errors]).to eq(0)
    expect(GoogleCalendarEvent.exists?(tracked_event.id)).to be(true)
  end

  it "does not delete anything in dry run mode" do
    expect(fake_service).not_to receive(:delete_event)

    result = job.perform(calendar.id, dry_run: true)

    expect(result[:deleted]).to eq(1)
  end

  it "treats an already-deleted event as success" do
    error = Google::Apis::ClientError.new("notFound", status_code: 404)
    allow(fake_service).to receive(:delete_event).and_raise(error)

    result = job.perform(calendar.id)

    expect(result[:errors]).to eq(0)
  end
end
