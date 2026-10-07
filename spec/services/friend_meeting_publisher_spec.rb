# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendMeetingPublisher, :microsoft_graph do
  include ActiveSupport::Testing::TimeHelpers

  let(:zone)   { Time.find_zone!("America/New_York") }
  let(:graph)  { MicrosoftGraphHelpers::GRAPH_URL }
  let(:user)   { create(:user) }
  let(:friend) { create(:user, first_name: "Sample", last_name: "Friend", email: "sample.friend@wit.edu") }
  let(:meeting) do
    create(:friend_meeting, :invite_friends, user: user, title: "Synthetic Study Group",
                                             start_time: zone.local(2026, 9, 15, 15), end_time: zone.local(2026, 9, 15, 16))
  end

  let(:google_credential) { create(:oauth_credential, user: user, access_token: "synthetic-user-token", token_expires_at: 1.hour.from_now) }
  let(:microsoft_credential) { create(:oauth_credential, :microsoft, user: user, token_expires_at: 1.hour.from_now) }
  let(:google_calendar) { create(:course_calendar, oauth_credential: google_credential, external_calendar_id: "synthetic-course-calendar") }
  let(:microsoft_calendar) do
    create(:course_calendar, :microsoft, oauth_credential: microsoft_credential, external_calendar_id: "AAMkSyntheticCalendar1")
  end

  let(:google_events_url)    { "#{GoogleApiStubs::GOOGLE_CALENDAR_API}/calendars/synthetic-course-calendar/events" }
  let(:microsoft_events_url) { "#{graph}/me/calendars/AAMkSyntheticCalendar1/events" }
  let(:google_created) do
    { status: 200, body: file_fixture("google_calendar/event_created.json").read, headers: { "Content-Type" => "application/json" } }
  end

  around { |example| travel_to(zone.local(2026, 9, 1, 12)) { example.run } }

  before { create(:friend_meeting_attendee, friend_meeting: meeting, user: friend) }

  after { Flipper.disable(FlipperFlags::MICROSOFT_GRAPH_CALENDAR) }

  def with_both_calendars
    Flipper.enable_actor(FlipperFlags::MICROSOFT_GRAPH_CALENDAR, user)
    google_calendar
    microsoft_calendar
  end

  def attendees_in(request)
    JSON.parse(request.body)["attendees"]
  end

  describe "#calendar_providers" do
    it "lists the providers that have a course calendar" do
      with_both_calendars

      expect(described_class.new(user).calendar_providers).to eq(%w[google microsoft])
    end

    it "is empty for a person who uses only the ICS feed" do
      expect(described_class.new(user).calendar_providers).to eq([])
    end
  end

  describe "#publish" do
    it "puts the meeting in each calendar, and only the first one invites the friends" do
      with_both_calendars
      google = stub_request(:post, google_events_url).with(query: { "sendUpdates" => "all" }) { |request| attendees_in(request).present? }
                                                       .to_return(google_created)
      microsoft = stub_request(:post, microsoft_events_url).with { |request| attendees_in(request).nil? }
                                                           .to_return(graph_json_response("meeting_created", status: 201))

      described_class.new(user).publish(meeting)

      expect(google).to have_been_requested.once
      expect(microsoft).to have_been_requested.once
      expect(meeting.calendar_events.pluck(:calendar_id)).to contain_exactly(google_calendar.id, microsoft_calendar.id)
    end

    it "skips a calendar that already has the meeting, so a retry is safe" do
      google_calendar
      create(:calendar_event, :for_friend_meeting, friend_meeting: meeting, course_calendar: google_calendar)

      described_class.new(user).publish(meeting)

      expect(a_request(:post, google_events_url).with(query: hash_including({}))).not_to have_been_made
    end

    it "still tries the other calendar when one provider fails, then raises the error" do
      with_both_calendars
      stub_request(:post, google_events_url).with(query: hash_including({}))
        .to_return(status: 500, body: { error: { code: 500, message: "Synthetic error" } }.to_json,
                   headers: { "Content-Type" => "application/json" })
      microsoft = stub_request(:post, microsoft_events_url).to_return(graph_json_response("meeting_created", status: 201))

      expect { described_class.new(user).publish(meeting) }.to raise_error(Google::Apis::ServerError)
      expect(microsoft).to have_been_requested.once
    end

    it "makes no request for a person who uses only the ICS feed" do
      expect { described_class.new(user).publish(meeting) }.not_to raise_error
      expect(meeting.calendar_events).to be_empty
    end
  end

  describe "#publish_missing" do
    it "puts back a meeting that is missing from a calendar" do
      google_calendar
      insert = stub_request(:post, google_events_url).with(query: hash_including({})).to_return(google_created)

      described_class.new(user).publish_missing

      expect(insert).to have_been_requested.once
      expect(meeting.calendar_events.count).to eq(1)
    end

    it "leaves a meeting that has ended alone" do
      google_calendar
      meeting.update_columns(start_time: zone.local(2026, 8, 1, 15), end_time: zone.local(2026, 8, 1, 16)) # rubocop:disable Rails/SkipsModelValidations

      described_class.new(user).publish_missing

      expect(a_request(:post, google_events_url).with(query: hash_including({}))).not_to have_been_made
    end

    it "logs a failure and does not raise it, so the course sync carries on" do
      google_calendar
      stub_request(:post, google_events_url).with(query: hash_including({}))
        .to_return(status: 500, body: { error: { code: 500, message: "Synthetic error" } }.to_json,
                   headers: { "Content-Type" => "application/json" })

      expect { described_class.new(user).publish_missing }.not_to raise_error
    end
  end
end
