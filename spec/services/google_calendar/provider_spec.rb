# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendar::Provider do
  it ".gone? is true for a 404 or a 410, and .rate_limited? for a RateLimitError" do
    expect(described_class.gone?(Google::Apis::ClientError.new("missing", status_code: 404))).to be(true)
    expect(described_class.gone?(Google::Apis::ClientError.new("deleted", status_code: 410))).to be(true)
    expect(described_class.gone?(Google::Apis::ClientError.new("conflict", status_code: 409))).to be(false)
    expect(described_class.rate_limited?(Google::Apis::RateLimitError.new("slow down", status_code: 429))).to be(true)
    expect(described_class.rate_limited?(Google::Apis::ServerError.new("down", status_code: 500))).to be(false)
  end

  describe "#update_calendar_events" do
    let(:user) { create(:user) }
    let(:credential) { create(:oauth_credential, user: user, token_expires_at: 1.hour.from_now) }
    let!(:course_calendar) { create(:course_calendar, oauth_credential: credential, last_synced_at: nil) }

    # The admin calendars page reads last_synced_at. Before this, only the
    # events got a sync time, so every Google calendar showed "Never synced".
    it "records the sync time on the calendar" do
      described_class.new(user).update_calendar_events([])

      expect(course_calendar.reload.last_synced_at).to be_within(1.minute).of(Time.current)
    end

    # With nothing to change, the sync sends no event call. It must still
    # refresh the token, so a revoked grant fails the sync and gets flagged.
    it "raises for a revoked grant when no event changed" do
      credential.update!(token_expires_at: 1.minute.ago, refresh_token: "synthetic-refresh")
      stub_request(:post, "https://oauth2.googleapis.com/token")
        .to_return(status: 400, body: { error: "invalid_grant" }.to_json, headers: { "Content-Type" => "application/json" })

      expect { described_class.new(user).update_calendar_events([]) }.to raise_error(Signet::AuthorizationError)
      expect(credential.reload).to be_token_revoked
      expect(course_calendar.reload.last_synced_at).to be_nil
    end
  end

  describe "#create_or_get_course_calendar" do
    let(:user) { create(:user) }

    before do
      stub_google_service_account
      allow_any_instance_of(described_class).to receive(:sleep)
    end

    # A job retries a RateLimitError later. A wrapped RuntimeError would make
    # the job fail with no retry.
    it "raises a rate limit as it is, so the job can retry it" do
      stub_request(:post, "https://www.googleapis.com/calendar/v3/calendars")
        .to_return(status: 403, body: file_fixture("google_calendar/rate_limit_exceeded.json").read,
                   headers: { "Content-Type" => "application/json" })

      expect { described_class.new(user).create_or_get_course_calendar }
        .to raise_error(Google::Apis::RateLimitError)
    end
  end

  describe "#create_friend_meeting_event" do
    let(:zone)       { Time.find_zone!("America/New_York") }
    let(:user)       { create(:user) }
    let(:friend)     { create(:user, first_name: "Sample", last_name: "Friend", email: "sample.friend@wit.edu") }
    let(:credential) { create(:oauth_credential, user: user, access_token: "synthetic-user-token", token_expires_at: 1.hour.from_now) }
    let(:events_url) { "#{GoogleApiStubs::GOOGLE_CALENDAR_API}/calendars/synthetic-course-calendar/events" }
    let(:meeting) do
      create(:friend_meeting, :invite_friends, user: user, title: "Synthetic Study Group", location: "Synthetic Library",
                                               start_time: zone.local(2026, 9, 15, 15), end_time: zone.local(2026, 9, 15, 16))
    end
    let(:created) { { status: 200, body: file_fixture("google_calendar/event_created.json").read, headers: { "Content-Type" => "application/json" } } }

    before { create(:friend_meeting_attendee, friend_meeting: meeting, user: friend) }

    it "returns nil when the person has no Google course calendar" do
      credential

      expect(described_class.new(user).create_friend_meeting_event(meeting)).to be_nil
    end

    context "with a course calendar" do
      before { create(:course_calendar, oauth_credential: credential, external_calendar_id: "synthetic-course-calendar") }

      it "creates the event with the friends as attendees, sends the invitations, and tracks it" do
        insert = stub_request(:post, events_url)
                 .with(query: { "sendUpdates" => "all" },
                       headers: { "Authorization" => "Bearer synthetic-user-token" },
                       body: hash_including("summary"   => "Synthetic Study Group",
                                            "location"  => "Synthetic Library",
                                            "attendees" => [ { "displayName" => "Sample Friend", "email" => "sample.friend@wit.edu" } ]))
                 .to_return(created)

        row = described_class.new(user).create_friend_meeting_event(meeting)

        expect(insert).to have_been_requested.once
        expect(row).to have_attributes(friend_meeting_id: meeting.id, external_event_id: "syntheticmeetingevent1",
                                       summary: "Synthetic Study Group", meeting_time_id: nil)
      end

      it "sends no attendees and no invitations when asked not to invite" do
        insert = stub_request(:post, events_url).with(query: { "sendUpdates" => "none" }) do |request|
          !JSON.parse(request.body).key?("attendees")
        end.to_return(created)

        described_class.new(user).create_friend_meeting_event(meeting, invite: false)

        expect(insert).to have_been_requested.once
      end

      it "sends the weekly rule of a weekly meeting" do
        meeting.update!(frequency: "weekly", term: create(:term), repeat_until: Date.new(2026, 12, 18))
        insert = stub_request(:post, events_url).with(query: hash_including({}),
                                                      body: hash_including("recurrence" => [ "RRULE:FREQ=WEEKLY;BYDAY=TU;UNTIL=20261219T045959Z" ]))
                                                .to_return(created)

        described_class.new(user).create_friend_meeting_event(meeting)

        expect(insert).to have_been_requested.once
      end

      it "deletes the new event when the meeting is already tracked in the calendar" do
        create(:calendar_event, :for_friend_meeting, friend_meeting: meeting, course_calendar: CourseCalendar.sole)
        stub_request(:post, events_url).with(query: hash_including({})).to_return(created)
        delete = stub_request(:delete, "#{events_url}/syntheticmeetingevent1").with(query: { "sendUpdates" => "none" }).to_return(status: 204)

        expect(described_class.new(user).create_friend_meeting_event(meeting)).to be_nil
        expect(delete).to have_been_requested.once
      end
    end
  end

  describe "an existing friend meeting event" do
    let(:zone)       { Time.find_zone!("America/New_York") }
    let(:user)       { create(:user) }
    let(:friend)     { create(:user, first_name: "Sample", last_name: "Friend", email: "sample.friend@wit.edu") }
    let(:credential) { create(:oauth_credential, user: user, access_token: "synthetic-user-token", token_expires_at: 1.hour.from_now) }
    let(:calendar)   { create(:course_calendar, oauth_credential: credential, external_calendar_id: "synthetic-course-calendar") }
    let(:events_url) { "#{GoogleApiStubs::GOOGLE_CALENDAR_API}/calendars/synthetic-course-calendar/events" }
    let(:event_url)  { "#{events_url}/gcal_synthetic_meeting" }
    let(:meeting) do
      create(:friend_meeting, :invite_friends, user: user, title: "Synthetic Review",
                                               start_time: zone.local(2026, 9, 15, 15), end_time: zone.local(2026, 9, 15, 16))
    end
    let(:row) do
      create(:calendar_event, :for_friend_meeting, course_calendar: calendar, friend_meeting: meeting, external_event_id: "gcal_synthetic_meeting")
    end
    let(:json) { { status: 200, body: file_fixture("google_calendar/event_created.json").read, headers: { "Content-Type" => "application/json" } } }

    before { create(:friend_meeting_attendee, friend_meeting: meeting, user: friend) }

    it "writes the meeting and its friends over the event and tells the friends" do
      put = stub_request(:put, event_url)
            .with(query: { "sendUpdates" => "all" },
                  body: hash_including("summary" => "Synthetic Review",
                                       "attendees" => [ { "displayName" => "Sample Friend", "email" => "sample.friend@wit.edu" } ]))
            .to_return(json)

      described_class.new(user).update_friend_meeting_event(row, meeting, attendees: true)

      expect(put).to have_been_requested.once
      expect(row.reload.summary).to eq("Synthetic Review")
    end

    it "sends an empty attendee list after the last friend leaves, so Google cancels for them" do
      meeting.friend_meeting_attendees.delete_all
      put = stub_request(:put, event_url).with(query: { "sendUpdates" => "all" }, body: hash_including("attendees" => []))
                                         .to_return(json)

      described_class.new(user).update_friend_meeting_event(row, meeting.reload, attendees: true)

      expect(put).to have_been_requested.once
    end

    it "makes a missing event again without attendees" do
      stub_request(:put, event_url).with(query: hash_including({}))
                                   .to_return(status: 404, body: { error: { code: 404, message: "Not Found" } }.to_json,
                                              headers: { "Content-Type" => "application/json" })
      insert = stub_request(:post, events_url).with(query: { "sendUpdates" => "none" }) { |request| !JSON.parse(request.body).key?("attendees") }
                                              .to_return(json)

      described_class.new(user).update_friend_meeting_event(row, meeting, attendees: true)

      expect(insert).to have_been_requested.once
      expect(CalendarEvent.exists?(row.id)).to be(false)
      expect(meeting.calendar_events.sole.external_event_id).to eq("syntheticmeetingevent1")
    end

    it "deletes the event with the person's token and sends the friends a cancellation" do
      delete = stub_request(:delete, event_url).with(query: { "sendUpdates" => "all" },
                                                     headers: { "Authorization" => "Bearer synthetic-user-token" })
                                               .to_return(status: 204)

      described_class.new(user).delete_friend_meeting_event(row)

      expect(delete).to have_been_requested.once
      expect(CalendarEvent.exists?(row.id)).to be(false)
    end

    it "counts an event that is already gone as deleted" do
      stub_request(:delete, event_url).with(query: hash_including({}))
                                      .to_return(status: 410, body: { error: { code: 410, message: "Gone" } }.to_json,
                                                 headers: { "Content-Type" => "application/json" })

      described_class.new(user).delete_friend_meeting_event(row)

      expect(CalendarEvent.exists?(row.id)).to be(false)
    end

    it "reads the declined attendees with the person's token, and not the tentative ones" do
      get = stub_request(:get, event_url).with(headers: { "Authorization" => "Bearer synthetic-user-token" })
                                         .to_return(status: 200, body: file_fixture("google_calendar/event_with_responses.json").read,
                                                    headers: { "Content-Type" => "application/json" })

      expect(described_class.new(user).declined_attendee_emails(row)).to eq([ "sample.friend@wit.edu" ])
      expect(get).to have_been_requested.once
    end

    it "finds no declined attendees on an event without attendees" do
      stub_request(:get, event_url).to_return(json)

      expect(described_class.new(user).declined_attendee_emails(row)).to eq([])
    end

    it "finds no declined attendees on an event that is gone" do
      stub_request(:get, event_url).to_return(status: 404, body: { error: { code: 404, message: "Not Found" } }.to_json,
                                              headers: { "Content-Type" => "application/json" })

      expect(described_class.new(user).declined_attendee_emails(row)).to eq([])
    end
  end

  describe "#update_calendar_events with a friend meeting" do
    let(:user)       { create(:user) }
    let(:credential) { create(:oauth_credential, user: user, token_expires_at: 1.hour.from_now) }
    let(:calendar)   { create(:course_calendar, oauth_credential: credential, external_calendar_id: "synthetic-course-calendar") }

    it "keeps the meeting row, because the meeting is not part of the schedule" do
      row = create(:calendar_event, :for_friend_meeting, course_calendar: calendar, end_time: 2.weeks.from_now)

      described_class.new(user).update_calendar_events([])

      expect(CalendarEvent.exists?(row.id)).to be(true)
    end
  end

  describe "#delete_events" do
    let(:user) { create(:user) }
    let(:credential) do
      create(:oauth_credential, user: user, access_token: "synthetic-user-token",
                                refresh_token: "synthetic-user-refresh",
                                token_expires_at: 1.hour.from_now)
    end
    let(:course_calendar) do
      create(:course_calendar, oauth_credential: credential, external_calendar_id: "synthetic-course-calendar")
    end
    let!(:db_event) do
      create(:calendar_event, :for_university_event, course_calendar: course_calendar,
                                                     external_event_id: "synthetic-event")
    end
    let(:event_url) { "#{GoogleApiStubs::GOOGLE_CALENDAR_API}/calendars/synthetic-course-calendar/events/synthetic-event" }

    it "deletes the event from Google and the database" do
      removal = stub_request(:delete, event_url)
        .with(headers: { "Authorization" => "Bearer synthetic-user-token" })
        .to_return(status: 204)

      described_class.new(user).delete_events([ db_event ])

      expect(removal).to have_been_requested.once
      expect(CalendarEvent.exists?(db_event.id)).to be(false)
    end

    # Google answers 410 Gone for an event the user already deleted. Before
    # this was handled, the error stopped every later sync for the user.
    it "treats an event that Google already deleted as done" do
      stub_request(:delete, event_url)
        .to_return(status: 410, body: { error: { code: 410, message: "Resource has been deleted" } }.to_json,
                   headers: { "Content-Type" => "application/json" })

      expect { described_class.new(user).delete_events([ db_event ]) }.not_to raise_error
      expect(CalendarEvent.exists?(db_event.id)).to be(false)
    end
  end
end
