# frozen_string_literal: true

require "rails_helper"

RSpec.describe CleanupUntrackedGoogleEventsJob do
  let(:user)       { create(:user) }
  let(:credential) { create(:oauth_credential, user: user) }
  let(:calendar)   { create(:google_calendar, oauth_credential: credential, google_calendar_id: "cal_123") }
  let(:meeting_time) { create(:course_meeting_time) }

  let!(:tracked_event) do
    create(:google_calendar_event, google_calendar: calendar, meeting_time: meeting_time, google_event_id: "tracked_1")
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
