# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cleanup::OrphanedCalendarEventsJob do
  let(:calendar) { create(:course_calendar, external_calendar_id: "google-cal-1") }
  let(:delete_url) { %r{\Ahttps://www\.googleapis\.com/calendar/v3/calendars/google-cal-1/events/[^/]+\z} }

  # The model validates that an event has exactly one owner, so an orphan only
  # exists after the owner row goes away. Clear the column to simulate that.
  def create_orphan(calendar: self.calendar, **attrs)
    event = create(:calendar_event, course_calendar: calendar, **attrs)
    event.update_columns(meeting_time_id: nil) # rubocop:disable Rails/SkipsModelValidations
    event
  end

  before do
    # A token that has not expired, so no refresh request goes out.
    calendar.oauth_credential.update!(token_expires_at: 1.hour.from_now, refresh_token: "synthetic-refresh-token")
  end

  it "keeps events that still have an owner" do
    kept = create(:calendar_event, course_calendar: calendar)

    result = described_class.perform_now

    expect(result).to eq(total: 0, deleted: 0, errors: 0)
    expect(CalendarEvent.exists?(kept.id)).to be(true)
  end

  it "deletes an orphan from Google and from the database" do
    orphan = create_orphan(external_event_id: "evt-1")
    stub = stub_request(:delete, "https://www.googleapis.com/calendar/v3/calendars/google-cal-1/events/evt-1")
           .to_return(status: 204)

    result = described_class.perform_now

    expect(stub).to have_been_requested
    expect(result).to eq(total: 1, deleted: 1, errors: 0)
    expect(CalendarEvent.exists?(orphan.id)).to be(false)
  end

  it "counts nothing and deletes nothing in a dry run" do
    orphan = create_orphan

    result = described_class.perform_now(dry_run: true)

    expect(result).to eq(total: 1, deleted: 0, errors: 0)
    expect(CalendarEvent.exists?(orphan.id)).to be(true)
    expect(a_request(:delete, delete_url)).not_to have_been_made
  end

  it "still deletes the row when Google says the event is already gone" do
    orphan = create_orphan(external_event_id: "evt-1")
    stub_request(:delete, delete_url).to_return(status: 404, body: { error: { code: 404, message: "Not Found" } }.to_json,
                                                headers: { "Content-Type" => "application/json" })

    result = described_class.perform_now

    expect(result[:deleted]).to eq(1)
    expect(CalendarEvent.exists?(orphan.id)).to be(false)
  end

  it "keeps the row and reports the error when Google refuses with another client error" do
    orphan = create_orphan(external_event_id: "evt-1")
    stub_request(:delete, delete_url).to_return(status: 403, body: { error: { code: 403, message: "Forbidden" } }.to_json,
                                                headers: { "Content-Type" => "application/json" })
    allow(Rails.error).to receive(:report)

    result = described_class.perform_now

    # The row is the only pointer to the remote event, so the next run tries again.
    expect(result).to eq(total: 1, deleted: 0, errors: 1)
    expect(CalendarEvent.exists?(orphan.id)).to be(true)
    expect(Rails.error).to have_received(:report)
      .with(an_instance_of(Google::Apis::ClientError), handled: true, context: { calendar_event_id: orphan.id })
  end

  it "does not call Google for a calendar without an external id" do
    orphan = create_orphan
    CourseCalendar.where(id: calendar.id).update_all(external_calendar_id: "") # rubocop:disable Rails/SkipsModelValidations

    described_class.perform_now

    expect(a_request(:delete, /googleapis/)).not_to have_been_made
    expect(CalendarEvent.exists?(orphan.id)).to be(false)
  end

  it "leaves the remote delete of a Microsoft event to the destroy callback" do
    microsoft_calendar = create(:course_calendar, :microsoft)
    orphan = create_orphan(calendar: microsoft_calendar, external_event_id: "ms-evt-1")

    expect { described_class.perform_now }
      .to have_enqueued_job(MicrosoftGraph::EventDeleteJob)
    expect(a_request(:delete, /googleapis/)).not_to have_been_made
    expect(CalendarEvent.exists?(orphan.id)).to be(false)
  end

  it "refreshes an expired token before it deletes, and saves the new token" do
    calendar.oauth_credential.update!(token_expires_at: 1.hour.ago)
    orphan = create_orphan(external_event_id: "evt-1")
    refresh = stub_request(:post, "https://oauth2.googleapis.com/token")
              .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                         body: { access_token: "synthetic-new-token", expires_in: 3600, token_type: "Bearer" }.to_json)
    stub_request(:delete, delete_url).to_return(status: 204)

    described_class.perform_now

    expect(refresh).to have_been_requested
    expect(calendar.oauth_credential.reload.access_token).to eq("synthetic-new-token")
    expect(CalendarEvent.exists?(orphan.id)).to be(false)
  end

  it "reports an error, counts it, and goes on to the next orphan" do
    broken = create_orphan(external_event_id: "evt-1")
    fine = create_orphan(external_event_id: "evt-2")
    stub_request(:delete, delete_url).to_return(status: 204)
    allow(Rails.error).to receive(:report)
    allow_any_instance_of(CalendarEvent).to receive(:destroy!).and_wrap_original do |original, *args|
      raise ActiveRecord::RecordNotDestroyed, "synthetic failure" if original.receiver.id == broken.id

      original.call(*args)
    end

    result = described_class.perform_now

    expect(result).to eq(total: 2, deleted: 1, errors: 1)
    expect(CalendarEvent.exists?(broken.id)).to be(true)
    expect(CalendarEvent.exists?(fine.id)).to be(false)
    expect(Rails.error).to have_received(:report)
      .with(an_instance_of(ActiveRecord::RecordNotDestroyed), handled: true, context: { calendar_event_id: broken.id })
  end
end
