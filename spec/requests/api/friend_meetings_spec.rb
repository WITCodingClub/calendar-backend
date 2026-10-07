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

    it "makes the meeting, starts the publish job, and answers with the meeting" do
      expect { post_meeting }.to have_enqueued_job(FriendMeetingPublishJob)

      meeting = FriendMeeting.sole
      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to eq(
        "meeting" => {
          "id"                 => meeting.public_id,
          "title"              => "Synthetic Study Group",
          "location"           => "Synthetic Library",
          "start_time"         => "2026-10-14T15:00:00-04:00",
          "end_time"           => "2026-10-14T16:00:00-04:00",
          "frequency"          => "weekly",
          "repeat_until"       => "2026-12-18",
          "invite_friends"     => true,
          "friends"            => [ { "id" => friend.public_id, "name" => "Sample Friend" } ],
          "calendar_providers" => []
        }
      )
    end

    it "lists the provider calendars that get the meeting" do
      credential = create(:oauth_credential, user: user)
      create(:course_calendar, oauth_credential: credential)

      post_meeting

      expect(response.parsed_body.dig("meeting", "calendar_providers")).to eq([ "google" ])
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
end
