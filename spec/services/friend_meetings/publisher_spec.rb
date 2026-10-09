# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendMeetings::Publisher, :microsoft_graph do
  include ActiveSupport::Testing::TimeHelpers

  let(:zone)   { Time.find_zone!("America/New_York") }
  let(:graph)  { MicrosoftGraphHelpers::GRAPH_URL }
  let(:user)   { create(:user) }
  let(:friend) { create(:user, first_name: "Sample", last_name: "Friend", email: "sample.friend@wit.edu") }
  let(:destinations) { %w[google microsoft ics] }
  let(:meeting) do
    create(:friend_meeting, :invite_friends, user: user, title: "Synthetic Study Group", destinations: destinations,
                                             start_time: zone.local(2026, 9, 15, 15), end_time: zone.local(2026, 9, 15, 16))
  end

  let(:google_credential) { create(:oauth_credential, user: user, access_token: "synthetic-user-token", token_expires_at: 1.hour.from_now) }
  let(:microsoft_credential) { create(:oauth_credential, :microsoft, user: user, token_expires_at: 1.hour.from_now) }
  let(:google_calendar) { create(:course_calendar, oauth_credential: google_credential, external_calendar_id: "synthetic-course-calendar") }
  let(:microsoft_calendar) do
    create(:course_calendar, :microsoft, oauth_credential: microsoft_credential, external_calendar_id: "AAMkSyntheticCalendar1")
  end

  let(:google_events_url)    { "#{GoogleApiStubs::GOOGLE_CALENDAR_API}/calendars/synthetic-course-calendar/events" }
  let(:microsoft_events_url) { "#{graph}/me/calendar/events" }
  let(:google_created) do
    { status: 200, body: file_fixture("google_calendar/event_created.json").read, headers: { "Content-Type" => "application/json" } }
  end

  around { |example| travel_to(zone.local(2026, 9, 1, 12)) { example.run } }

  before { create(:friend_meeting_attendee, friend_meeting: meeting, user: friend) }

  after { Flipper.disable(FeatureFlags::MICROSOFT_GRAPH_CALENDAR) }

  def with_both_calendars
    Flipper.enable_actor(FeatureFlags::MICROSOFT_GRAPH_CALENDAR, user)
    google_calendar
    microsoft_calendar
  end

  def attendees_in(request)
    JSON.parse(request.body)["attendees"]
  end

  def publication(provider) = meeting.publications.find_by!(provider: provider)

  def google_error(status)
    { status: status, body: { error: { code: status, message: "Synthetic error" } }.to_json, headers: { "Content-Type" => "application/json" } }
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
      expect(publication("google")).to have_attributes(status: "published", invitation_status: "sent")
      expect(publication("microsoft")).to have_attributes(status: "published", invitation_status: "not_requested")
    end

    context "when the person picked only Microsoft" do
      let(:destinations) { %w[microsoft] }

      it "writes only to Microsoft, which sends the invitations" do
        with_both_calendars
        microsoft = stub_request(:post, microsoft_events_url).with { |request| attendees_in(request).present? }
                                                             .to_return(graph_json_response("meeting_created", status: 201))

        described_class.new(user).publish(meeting)

        expect(microsoft).to have_been_requested.once
        expect(a_request(:post, google_events_url).with(query: hash_including({}))).not_to have_been_made
      end
    end

    it "never sends the invitations twice" do
      google_calendar
      publication("google").update!(invitations_sent_at: 1.day.ago)
      insert = stub_request(:post, google_events_url).with(query: { "sendUpdates" => "none" }) { |request| attendees_in(request).nil? }
                                                     .to_return(google_created)

      described_class.new(user).publish(meeting)

      expect(insert).to have_been_requested.once
    end

    it "does nothing for a cancelled meeting" do
      google_calendar
      meeting.update!(cancelled_at: Time.current)

      described_class.new(user).publish(meeting)

      expect(a_request(:post, google_events_url).with(query: hash_including({}))).not_to have_been_made
    end

    it "marks a picked calendar that is no longer connected as failed" do
      described_class.new(user).publish(meeting)

      expect(publication("google")).to have_attributes(status: "failed", invitation_status: "failed")
    end

    it "skips a calendar that already has the meeting, so a retry is safe" do
      google_calendar
      create(:calendar_event, :for_friend_meeting, friend_meeting: meeting, course_calendar: google_calendar)

      described_class.new(user).publish(meeting)

      expect(a_request(:post, google_events_url).with(query: hash_including({}))).not_to have_been_made
    end

    it "still tries the other calendar when one provider fails, then raises the error" do
      with_both_calendars
      stub_request(:post, google_events_url).with(query: hash_including({})).to_return(google_error(500))
      microsoft = stub_request(:post, microsoft_events_url).to_return(graph_json_response("meeting_created", status: 201))

      expect { described_class.new(user).publish(meeting) }.to raise_error(Google::Apis::ServerError)
      expect(microsoft).to have_been_requested.once
      expect(publication("google")).to have_attributes(status: "failed", last_error: "Google::Apis::ServerError")
      expect(publication("microsoft")).to be_published
    end

    context "when the person uses only the ICS feed" do
      let(:destinations) { %w[ics] }

      it "makes no request" do
        expect { described_class.new(user).publish(meeting) }.not_to raise_error
        expect(meeting.calendar_events).to be_empty
      end
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
      stub_request(:post, google_events_url).with(query: hash_including({})).to_return(google_error(500))

      expect { described_class.new(user).publish_missing }.not_to raise_error
    end

    it "puts a meeting back without attendees after the invitations went out" do
      google_calendar
      publication("google").update!(invitations_sent_at: 1.day.ago, status: "published")
      insert = stub_request(:post, google_events_url).with(query: { "sendUpdates" => "none" }) { |request| attendees_in(request).nil? }
                                                     .to_return(google_created)

      described_class.new(user).publish_missing

      expect(insert).to have_been_requested.once
    end

    it "costs one query for a person with no meetings" do
      other = create(:user)
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        described_class.new(other, services: []).publish_missing
      end

      expect(queries.size).to eq(1)
      expect(queries.first).to match(/SELECT 1 AS one FROM "friend_meetings"/)
    end
  end

  describe "#remove_declined" do
    let(:destinations) { %w[google ics] }
    let(:maybe_friend) { create(:user, email: "maybe.friend@wit.edu") }
    let(:event_url)    { "#{google_events_url}/gcal_synthetic_meeting" }
    let(:responses) do
      { status: 200, body: file_fixture("google_calendar/event_with_responses.json").read, headers: { "Content-Type" => "application/json" } }
    end

    before do
      create(:friend_meeting_attendee, friend_meeting: meeting, user: maybe_friend)
      create(:calendar_event, :for_friend_meeting, friend_meeting: meeting, course_calendar: google_calendar,
                                                   external_event_id: "gcal_synthetic_meeting")
      publication("google").update!(invitations_sent_at: 1.day.ago, status: "published")
    end

    it "takes off a friend who declined, keeps a tentative friend, and sends no update" do
      stub_request(:get, event_url).to_return(responses)

      expect { described_class.new(user).remove_declined }.not_to have_enqueued_job(FriendMeetings::UpdateJob)

      expect(meeting.attendees.reload).to contain_exactly(maybe_friend)
      expect(FriendMeeting.inviting(friend)).not_to exist
    end

    it "reads nothing before the invitations went out" do
      publication("google").update!(invitations_sent_at: nil)

      described_class.new(user).remove_declined

      expect(a_request(:get, event_url)).not_to have_been_made
      expect(meeting.attendees.reload).to contain_exactly(friend, maybe_friend)
    end

    it "reads nothing for a meeting that did not invite the friends" do
      meeting.update!(invite_friends: false)

      described_class.new(user).remove_declined

      expect(a_request(:get, event_url)).not_to have_been_made
    end

    it "reads nothing for a meeting that has ended" do
      meeting.update_columns(start_time: zone.local(2026, 8, 1, 15), end_time: zone.local(2026, 8, 1, 16)) # rubocop:disable Rails/SkipsModelValidations

      described_class.new(user).remove_declined

      expect(a_request(:get, event_url)).not_to have_been_made
    end

    it "reports a failure and does not raise it, so the course sync carries on" do
      stub_request(:get, event_url).to_return(google_error(500))
      allow(Rails.error).to receive(:report)

      expect { described_class.new(user).remove_declined }.not_to raise_error
      expect(Rails.error).to have_received(:report)
        .with(an_instance_of(Google::Apis::ServerError), handled: true, context: { user_id: user.id, friend_meeting_id: meeting.id })
      expect(meeting.attendees.reload).to contain_exactly(friend, maybe_friend)
    end

    it "costs one query for a person with no meetings that invite friends" do
      other = create(:user)
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        described_class.new(other, services: []).remove_declined
      end

      expect(queries.size).to eq(1)
    end
  end

  describe "#update" do
    before { google_calendar }

    let(:row) do
      create(:calendar_event, :for_friend_meeting, friend_meeting: meeting, course_calendar: google_calendar,
                                                   external_event_id: "gcal_synthetic_meeting")
    end
    let(:destinations) { %w[google ics] }

    it "writes the change with the friends when this calendar sent the invitations" do
      row
      publication("google").update!(invitations_sent_at: 1.day.ago)
      put = stub_request(:put, "#{google_events_url}/gcal_synthetic_meeting").with(query: { "sendUpdates" => "all" })
                                                                              .to_return(google_created)

      described_class.new(user).update(meeting)

      expect(put).to have_been_requested.once
      expect(publication("google")).to be_published
    end

    it "makes the event when the calendar does not have it yet" do
      insert = stub_request(:post, google_events_url).with(query: { "sendUpdates" => "all" }).to_return(google_created)

      described_class.new(user).update(meeting)

      expect(insert).to have_been_requested.once
      expect(publication("google").invitation_status).to eq("sent")
    end
  end

  describe "#remove" do
    let(:destinations) { %w[google microsoft ics] }

    it "deletes each provider event with a cancellation, then the meeting" do
      with_both_calendars
      create(:calendar_event, :for_friend_meeting, friend_meeting: meeting, course_calendar: google_calendar, external_event_id: "gcal_synthetic_meeting")
      create(:calendar_event, :for_friend_meeting, friend_meeting: meeting, course_calendar: microsoft_calendar, external_event_id: "AAMkSyntheticMeeting1")
      google    = stub_request(:delete, "#{google_events_url}/gcal_synthetic_meeting").with(query: { "sendUpdates" => "all" }).to_return(status: 204)
      microsoft = stub_request(:delete, "#{graph}/me/events/AAMkSyntheticMeeting1").to_return(status: 204)

      described_class.new(user).remove(meeting)

      expect(google).to have_been_requested.once
      expect(microsoft).to have_been_requested.once
      expect(FriendMeeting.exists?(meeting.id)).to be(false)
    end

    it "keeps the row and records a refused token without raising, so a reconnect can finish" do
      google_calendar
      meeting.update!(cancelled_at: Time.current)
      row = create(:calendar_event, :for_friend_meeting, friend_meeting: meeting, course_calendar: google_calendar,
                                                         external_event_id: "gcal_synthetic_meeting")
      stub_request(:delete, "#{google_events_url}/gcal_synthetic_meeting").with(query: hash_including({}))
        .to_return(google_error(401))

      expect { described_class.new(user).remove(meeting) }.not_to raise_error
      expect(CalendarEvent.exists?(row.id)).to be(true)
      expect(meeting.reload).to be_cancelled
      expect(publication("google")).to have_attributes(status: "failed", last_error: "Google::Apis::AuthorizationError")
    end

    it "keeps the cancelled meeting when a delete fails, so a retry can finish" do
      google_calendar
      meeting.update!(cancelled_at: Time.current)
      create(:calendar_event, :for_friend_meeting, friend_meeting: meeting, course_calendar: google_calendar, external_event_id: "gcal_synthetic_meeting")
      stub_request(:delete, "#{google_events_url}/gcal_synthetic_meeting").with(query: hash_including({})).to_return(google_error(500))

      expect { described_class.new(user).remove(meeting) }.to raise_error(Google::Apis::ServerError)
      expect(meeting.reload).to be_cancelled
    end
  end

  describe "#resume" do
    let(:destinations) { %w[google ics] }

    it "finishes a cancelled meeting and puts back a missing event" do
      google_calendar
      cancelled = create(:friend_meeting, :cancelled, user: user, destinations: %w[google])
      create(:calendar_event, :for_friend_meeting, friend_meeting: cancelled, course_calendar: google_calendar,
                                                   external_event_id: "gcal_cancelled")
      delete = stub_request(:delete, "#{google_events_url}/gcal_cancelled").with(query: hash_including({})).to_return(status: 204)
      insert = stub_request(:post, google_events_url).with(query: hash_including({})).to_return(google_created)

      described_class.new(user).resume

      expect(delete).to have_been_requested.once
      expect(FriendMeeting.exists?(cancelled.id)).to be(false)
      expect(insert).to have_been_requested.once
      expect(meeting.calendar_events.count).to eq(1)
    end
  end

  describe "a Microsoft disconnect" do
    let(:destinations) { %w[microsoft] }

    it "keeps the publication removed while the calendar is gone, then invites again after a reconnect" do
      Flipper.enable_actor(FeatureFlags::MICROSOFT_GRAPH_CALENDAR, user)
      publication("microsoft").update!(status: "published", invitations_sent_at: 1.day.ago)
      publication("microsoft").mark_removed!

      described_class.new(user).publish(meeting)
      expect(publication("microsoft")).to have_attributes(status: "removed", invitation_status: "cancelled")

      microsoft_calendar
      invite = stub_request(:post, microsoft_events_url).with { |request| attendees_in(request).present? }
                                                        .to_return(graph_json_response("meeting_created", status: 201))

      described_class.new(user).publish_missing

      expect(invite).to have_been_requested.once
      expect(publication("microsoft")).to have_attributes(status: "published", invitation_status: "sent")
    end
  end
end
