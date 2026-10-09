# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cleanup::DuplicateTbdEventsJob do
  let(:user) { create(:user) }
  let(:credential) { create(:oauth_credential, user: user) }
  let!(:calendar) { create(:course_calendar, oauth_credential: credential, external_calendar_id: "google-cal-1") }
  let(:course) { create(:course) }
  let(:api_service) { instance_double(Google::Apis::CalendarV3::CalendarService, delete_event: nil) }
  let(:provider) { instance_double(GoogleCalendar::Provider, user_calendar_service: api_service) }

  before do
    allow(GoogleCalendar::Provider).to receive(:new).and_return(provider)
    # The job calls the private method through send.
    allow(provider).to receive(:send).with(:user_calendar_service).and_return(api_service)
  end

  # Two meeting times for one course slot, so their events are duplicates.
  def meeting_time(room: nil, **attrs)
    mt = create(:course_meeting_time, course: course, **attrs)
    create(:course_meeting_time_room, meeting_time: mt, room: room) if room
    mt
  end

  def event_for(meeting_time, external_event_id)
    create(:calendar_event, course_calendar: calendar, meeting_time: meeting_time, external_event_id: external_event_id)
  end

  let(:valid_room) { create(:room, number: "101") }
  let!(:valid_event) { event_for(meeting_time(room: valid_room), "valid-evt") }
  let!(:tbd_event) { event_for(meeting_time, "tbd-evt") }

  it "deletes the TBD duplicate from Google and the database, and keeps the valid event" do
    described_class.perform_now(user.id)

    expect(api_service).to have_received(:delete_event).with("google-cal-1", "tbd-evt")
    expect(CalendarEvent.exists?(tbd_event.id)).to be(false)
    expect(CalendarEvent.exists?(valid_event.id)).to be(true)
  end

  it "finds users with course calendars when it gets no user id" do
    create(:user) # no course calendar, so the job skips this user

    described_class.perform_now

    expect(CalendarEvent.exists?(tbd_event.id)).to be(false)
  end

  it "treats a room number of zero as TBD" do
    zero_room = create(:room, number: "0")
    zero_event = event_for(meeting_time(room: zero_room), "zero-evt")

    described_class.perform_now(user.id)

    expect(CalendarEvent.exists?(zero_event.id)).to be(false)
    expect(CalendarEvent.exists?(tbd_event.id)).to be(false)
  end

  it "treats a building named TBD as TBD" do
    building = create(:building, name: "Location TBD", abbreviation: "FCTX")
    tbd_building_event = event_for(meeting_time(room: create(:room, building: building, number: "205")), "tbd-building-evt")

    described_class.perform_now(user.id)

    expect(CalendarEvent.exists?(tbd_building_event.id)).to be(false)
  end

  it "keeps a TBD event when no valid event shares its slot" do
    CalendarEvent.where(id: valid_event.id).destroy_all

    described_class.perform_now(user.id)

    expect(api_service).not_to have_received(:delete_event)
    expect(CalendarEvent.exists?(tbd_event.id)).to be(true)
  end

  it "keeps events whose meeting times are in different slots" do
    other_slot = event_for(meeting_time(day_of_week: :tuesday), "other-slot-evt")

    described_class.perform_now(user.id)

    expect(CalendarEvent.exists?(other_slot.id)).to be(true)
  end

  it "does nothing for a user with no Google course calendar" do
    other_user = create(:user)

    described_class.perform_now(other_user.id)

    expect(GoogleCalendar::Provider).not_to have_received(:new)
  end

  it "removes the row when Google says the event is already gone" do
    allow(api_service).to receive(:delete_event).and_raise(Google::Apis::ClientError.new("notFound", status_code: 404))

    described_class.perform_now(user.id)

    expect(CalendarEvent.exists?(tbd_event.id)).to be(false)
  end

  it "keeps the row and reports the error when Google refuses with another client error" do
    error = Google::Apis::ClientError.new("forbidden", status_code: 403)
    allow(api_service).to receive(:delete_event).and_raise(error)
    allow(Rails.error).to receive(:report)

    described_class.perform_now(user.id)

    expect(CalendarEvent.exists?(tbd_event.id)).to be(true)
    expect(Rails.error).to have_received(:report)
      .with(error, handled: true, context: { user_id: user.id, calendar_event_id: tbd_event.id })
  end

  it "reports an unexpected error instead of raising it" do
    error = StandardError.new("synthetic failure")
    allow(api_service).to receive(:delete_event).and_raise(error)
    allow(Rails.error).to receive(:report)

    expect { described_class.perform_now(user.id) }.not_to raise_error

    expect(Rails.error).to have_received(:report).with(error, handled: true, context: { user_id: user.id })
  end
end
