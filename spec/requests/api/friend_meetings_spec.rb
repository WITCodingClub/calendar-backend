# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::FriendMeetings", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:zone)   { Time.find_zone!("America/New_York") }
  let(:user)   { create(:user) }
  let(:friend) { create(:user, first_name: "Sample", last_name: "Friend") }
  let(:params) do
    {
      title:          "Synthetic Study Group",
      start_time:     "2026-10-14T15:00:00-04:00",
      end_time:       "2026-10-14T16:00:00-04:00",
      location:       "Synthetic Library",
      friend_ids:     [ friend.public_id ],
      frequency:      "weekly",
      invite_friends: true
    }
  end

  around { |example| travel_to(zone.local(2026, 10, 7, 12)) { example.run } }

  before do
    create(:friendship, :accepted, requester: friend, addressee: user)
    create(:term, start_date: Date.new(2026, 9, 2), end_date: Date.new(2026, 12, 18))
  end

  after { Flipper.disable(FlipperFlags::FRIEND_MEETING_EVENTS) }

  def post_meeting(body = params)
    post "/api/friends/meetings", params: body, headers: auth_headers_for(user), as: :json
  end

  it "answers 404 while the flag is off, and makes nothing" do
    post_meeting

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq("error" => "Friend meeting events are not enabled")
    expect(FriendMeeting.count).to eq(0)
  end

  it "answers 401 without a token" do
    post "/api/friends/meetings", params: params, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  context "when the flag is on for the person" do
    before { Flipper.enable_actor(FlipperFlags::FRIEND_MEETING_EVENTS, user) }

    def connect_google
      credential = create(:oauth_credential, user: user)
      create(:course_calendar, oauth_credential: credential)
    end

    it "makes the meeting, starts the publish job, and answers with the meeting" do
      connect_google

      expect { post_meeting }.to have_enqueued_job(FriendMeetingPublishJob)

      meeting = FriendMeeting.sole
      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to eq(
        "meeting" => {
          "id"             => meeting.public_id,
          "title"          => "Synthetic Study Group",
          "location"       => "Synthetic Library",
          "start_time"     => "2026-10-14T15:00:00-04:00",
          "end_time"       => "2026-10-14T16:00:00-04:00",
          "time_zone"      => "America/New_York",
          "frequency"      => "weekly",
          "recurrence"     => "RRULE:FREQ=WEEKLY;BYDAY=WE;UNTIL=20261219T045959Z",
          "repeat_until"   => "2026-12-18",
          "invite_friends" => true,
          "role"           => "owner",
          "can_edit"       => true,
          "can_delete"     => true,
          "can_leave"      => false,
          "owner"          => { "id" => user.public_id, "name" => user.full_name },
          "friends"        => [ { "id" => friend.public_id, "name" => "Sample Friend" } ],
          "guest"          => nil,
          "destinations"   => %w[google ics],
          "publications"   => [
            { "provider" => "google", "status" => "queued", "invitation_status" => "queued" },
            { "provider" => "ics", "status" => "published", "invitation_status" => "not_requested" }
          ]
        }
      )
    end

    it "sends the meeting only to the places in destinations" do
      connect_google

      expect { post_meeting(params.merge(destinations: [ "ics" ])) }.not_to have_enqueued_job(FriendMeetingPublishJob)

      expect(response.parsed_body.dig("meeting", "destinations")).to eq([ "ics" ])
    end

    it "answers 422 for a place that is not connected" do
      post_meeting(params.merge(destinations: [ "microsoft" ]))

      expect(response).to have_http_status(:unprocessable_content)
      expect(FriendMeeting.count).to eq(0)
    end

    it "answers a retry with the same Idempotency-Key with the first meeting, and sends nothing again" do
      connect_google
      headers = auth_headers_for(user).merge("Idempotency-Key" => "synthetic-retry-key")
      post "/api/friends/meetings", params: params, headers: headers, as: :json
      first_id = response.parsed_body.dig("meeting", "id")

      expect do
        post "/api/friends/meetings", params: params, headers: headers, as: :json
      end.not_to have_enqueued_job(FriendMeetingPublishJob)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("meeting", "id")).to eq(first_id)
      expect(FriendMeeting.count).to eq(1)
    end

    it "takes the key as a parameter too" do
      2.times { post_meeting(params.merge(idempotency_key: "synthetic-param-key")) }

      expect(FriendMeeting.count).to eq(1)
    end

    it "answers 422 for a person who is not an accepted friend" do
      stranger = create(:user)

      post_meeting(params.merge(friend_ids: [ stranger.public_id ]))

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("#{stranger.public_id} is not one of your accepted friends")
      expect(FriendMeeting.count).to eq(0)
    end

    it "answers 422 when the end is before the start" do
      post_meeting(params.merge(end_time: "2026-10-14T14:00:00-04:00"))

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("End time must be after the start time")
    end

    it "answers 400 when a required field is missing" do
      post_meeting(params.except(:title))

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /api/friends/meetings" do
    let(:weekly) do
      create(:friend_meeting, :invite_friends, user: user, title: "Synthetic Weekly", frequency: "weekly",
                                               term: Term.sole, repeat_until: Date.new(2026, 12, 18), destinations: %w[ics],
                                               start_time: zone.local(2026, 10, 14, 15), end_time: zone.local(2026, 10, 14, 16))
    end

    before do
      Flipper.enable_actor(FlipperFlags::FRIEND_MEETING_EVENTS, user)
      Flipper.enable_actor(FlipperFlags::FRIEND_MEETING_EVENTS, friend)
      create(:friend_meeting_attendee, friend_meeting: weekly, user: friend)
    end

    def list(person = user, range = { start: "2026-10-12", end: "2026-10-26" })
      get "/api/friends/meetings", params: range, headers: auth_headers_for(person)
    end

    it "lists each occurrence in the range with a stable id, for a person with no provider calendar" do
      list

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["meetings"].map { |m| m["id"] }).to eq([ weekly.public_id ])
      expect(response.parsed_body["occurrences"]).to eq([
        { "id" => "#{weekly.public_id}:2026-10-14T19:00:00Z", "meeting_id" => weekly.public_id,
          "start_time" => "2026-10-14T15:00:00-04:00", "end_time" => "2026-10-14T16:00:00-04:00" },
        { "id" => "#{weekly.public_id}:2026-10-21T19:00:00Z", "meeting_id" => weekly.public_id,
          "start_time" => "2026-10-21T15:00:00-04:00", "end_time" => "2026-10-21T16:00:00-04:00" }
      ])
    end

    it "keeps the local time after daylight saving time ends" do
      list(user, { start: "2026-11-02T00:00:00-05:00", end: "2026-11-09T00:00:00-05:00" })

      expect(response.parsed_body["occurrences"].sole["start_time"]).to eq("2026-11-04T15:00:00-05:00")
    end

    it "shows an invited friend the meeting as an invitee who cannot change it" do
      list(friend)

      meeting = response.parsed_body["meetings"].sole
      expect(meeting).to include("id" => weekly.public_id, "role" => "invitee", "can_edit" => false, "can_delete" => false,
                                 "can_leave" => true,
                                 "owner" => { "id" => user.public_id, "name" => user.full_name }, "publications" => [], "destinations" => [])
      expect(response.parsed_body["occurrences"].size).to eq(2)
    end

    it "hides a meeting from a friend that the owner did not invite" do
      weekly.update!(invite_friends: false)

      list(friend)

      expect(response.parsed_body).to eq("meetings" => [], "occurrences" => [])
    end

    it "hides a deleted meeting and a stranger's meeting" do
      create(:friend_meeting, user: create(:user), start_time: zone.local(2026, 10, 15, 15), end_time: zone.local(2026, 10, 15, 16))
      weekly.update!(cancelled_at: Time.current)

      list

      expect(response.parsed_body["meetings"]).to be_empty
    end

    it "answers 400 for a missing or bad range" do
      list(user, { start: "2026-10-12" })
      expect(response).to have_http_status(:bad_request)

      list(user, { start: "2026-10-26", end: "2026-10-12" })
      expect(response).to have_http_status(:bad_request)

      list(user, { start: "2026-01-01", end: "2027-06-01" })
      expect(response).to have_http_status(:bad_request)

      list(user, { start: "soon", end: "2026-10-12" })
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET, PATCH, and DELETE /api/friends/meetings/:id" do
    let(:meeting) do
      create(:friend_meeting, :invite_friends, user: user, title: "Synthetic Study Group", destinations: %w[google ics],
                                               start_time: zone.local(2026, 10, 14, 15), end_time: zone.local(2026, 10, 14, 16))
    end
    let(:stranger) { create(:user) }

    before do
      [ user, friend, stranger ].each { |person| Flipper.enable_actor(FlipperFlags::FRIEND_MEETING_EVENTS, person) }
      create(:friend_meeting_attendee, friend_meeting: meeting, user: friend)
    end

    it "shows the meeting to the owner and to an invited friend, and answers 404 to anyone else" do
      get "/api/friends/meetings/#{meeting.public_id}", headers: auth_headers_for(user)
      expect(response.parsed_body.dig("meeting", "publications").map { |p| p["provider"] }).to eq(%w[google ics])

      get "/api/friends/meetings/#{meeting.public_id}", headers: auth_headers_for(friend)
      expect(response.parsed_body.dig("meeting", "role")).to eq("invitee")

      get "/api/friends/meetings/#{meeting.public_id}", headers: auth_headers_for(stranger)
      expect(response).to have_http_status(:not_found)

      get "/api/friends/meetings/#{meeting.id}", headers: auth_headers_for(user)
      expect(response).to have_http_status(:not_found)
    end

    it "lets the owner change the whole series and starts the update job" do
      expect do
        patch "/api/friends/meetings/#{meeting.public_id}",
              params: { title: "Synthetic Review", location: "Synthetic Hall", start_time: "2026-10-15T10:00:00-04:00",
                        end_time: "2026-10-15T11:00:00-04:00" },
              headers: auth_headers_for(user), as: :json
      end.to have_enqueued_job(FriendMeetingUpdateJob).with(meeting)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["meeting"]).to include("title" => "Synthetic Review", "location" => "Synthetic Hall",
                                                         "start_time" => "2026-10-15T10:00:00-04:00")
      expect(response.parsed_body.dig("meeting", "publications").first["status"]).to eq("queued")
    end

    it "answers 422 for a change that is not valid" do
      patch "/api/friends/meetings/#{meeting.public_id}", params: { end_time: "2026-10-14T14:00:00-04:00" },
                                                          headers: auth_headers_for(user), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(meeting.reload.end_time).to eq(zone.local(2026, 10, 14, 16))
    end

    it "answers 403 when an invited friend tries to change or delete the meeting" do
      patch "/api/friends/meetings/#{meeting.public_id}", params: { title: "Synthetic Takeover" },
                                                          headers: auth_headers_for(friend), as: :json
      expect(response).to have_http_status(:forbidden)

      delete "/api/friends/meetings/#{meeting.public_id}", headers: auth_headers_for(friend)
      expect(response).to have_http_status(:forbidden)
      expect(meeting.reload).not_to be_cancelled
    end

    it "deletes the meeting for the owner at once and starts the remove job" do
      expect do
        delete "/api/friends/meetings/#{meeting.public_id}", headers: auth_headers_for(user)
      end.to have_enqueued_job(FriendMeetingRemoveJob).with(meeting)

      expect(response).to have_http_status(:no_content)
      expect(meeting.reload).to be_cancelled

      get "/api/friends/meetings/#{meeting.public_id}", headers: auth_headers_for(user)
      expect(response).to have_http_status(:not_found)
    end

    it "keeps a deleted meeting out of a later sync" do
      delete "/api/friends/meetings/#{meeting.public_id}", headers: auth_headers_for(user)
      credential = create(:oauth_credential, user: user)
      create(:course_calendar, oauth_credential: credential)

      FriendMeetingPublisher.new(user).publish_missing

      expect(meeting.calendar_events).to be_empty
    end

    it "answers 404 while the flag is off" do
      Flipper.disable_actor(FlipperFlags::FRIEND_MEETING_EVENTS, user)

      delete "/api/friends/meetings/#{meeting.public_id}", headers: auth_headers_for(user)

      expect(response).to have_http_status(:not_found)
      expect(meeting.reload).not_to be_cancelled
    end
  end

  describe "DELETE /api/friends/meetings/:id/attendance" do
    let(:meeting) do
      create(:friend_meeting, :invite_friends, user: user, destinations: %w[ics],
                                               start_time: zone.local(2026, 10, 14, 15), end_time: zone.local(2026, 10, 14, 16))
    end

    before do
      [ user, friend ].each { |person| Flipper.enable_actor(FlipperFlags::FRIEND_MEETING_EVENTS, person) }
      create(:friend_meeting_attendee, friend_meeting: meeting, user: friend)
    end

    def leave(person = friend)
      delete "/api/friends/meetings/#{meeting.public_id}/attendance", headers: auth_headers_for(person)
    end

    it "takes the invited friend off the meeting and starts the update job" do
      expect { leave }.to have_enqueued_job(FriendMeetingUpdateJob).with(meeting)

      expect(response).to have_http_status(:no_content)
      expect(meeting.attendees).to be_empty
      expect(meeting.reload).not_to be_cancelled
    end

    it "removes the meeting from the friend's list and busy blocks" do
      leave

      get "/api/friends/meetings", params: { start: "2026-10-12", end: "2026-10-19" }, headers: auth_headers_for(friend)
      expect(response.parsed_body["meetings"]).to be_empty

      get "/api/user/busy_blocks", params: { start_date: "2026-10-14", end_date: "2026-10-14" }, headers: auth_headers_for(friend)
      expect(response.parsed_body["busy"]).to be_empty
    end

    it "starts no job for a meeting that has ended" do
      meeting.update_columns(start_time: zone.local(2026, 10, 1, 15), end_time: zone.local(2026, 10, 1, 16))

      expect { leave }.not_to have_enqueued_job(FriendMeetingUpdateJob)
      expect(meeting.attendees).to be_empty
    end

    it "answers 403 to the owner, who deletes the meeting instead" do
      leave(user)

      expect(response).to have_http_status(:forbidden)
      expect(meeting.attendees).to contain_exactly(friend)
    end

    it "answers 404 to a person who cannot see the meeting" do
      stranger = create(:user)
      Flipper.enable_actor(FlipperFlags::FRIEND_MEETING_EVENTS, stranger)

      leave(stranger)

      expect(response).to have_http_status(:not_found)
    end

    it "answers 404 to a friend who already left" do
      leave
      leave

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/friends/:friend_id with a shared meeting" do
    it "takes the ex-friend off the meeting and updates its provider events" do
      meeting = create(:friend_meeting, :invite_friends, user: user, destinations: %w[ics],
                                                         start_time: zone.local(2026, 10, 14, 15), end_time: zone.local(2026, 10, 14, 16))
      create(:friend_meeting_attendee, friend_meeting: meeting, user: friend)

      expect do
        delete "/api/friends/#{friend.public_id}", headers: auth_headers_for(user)
      end.to have_enqueued_job(FriendMeetingUpdateJob).with(meeting)

      expect(response).to have_http_status(:ok)
      expect(meeting.attendees).to be_empty
    end
  end
end
