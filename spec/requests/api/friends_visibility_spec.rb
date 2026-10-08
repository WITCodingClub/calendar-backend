# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Friends availability-only sharing", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:viewer)  { create(:user) }
  let(:friend)  { create(:user) }
  let(:headers) { auth_headers_for(viewer) }
  let(:term)    { create(:term) }
  let!(:friendship) { create(:friendship, :accepted, requester: viewer, addressee: friend) }

  # Distinct values, so a leak of any of them shows up in the raw body.
  let(:building) { create(:building, name: "Zyxwv Hall", abbreviation: "ZYXQ") }
  let(:faculty)  { create(:faculty, first_name: "Quillon", last_name: "Vexmarch", email: "qvexmarch@example.edu") }
  let(:course) do
    create(:course, term: term, crn: 98_765, subject: "QXZY", course_number: 4321, title: "Secret Topology Seminar")
  end
  let!(:meeting_time) do
    create(:course_meeting_time, course: course, day_of_week: :monday, begin_time: 900, end_time: 1015)
  end

  before do
    create(:course_faculty, course: course, faculty: faculty)
    create(:course_meeting_time_room, meeting_time: meeting_time, room: create(:room, building: building, number: "777"))
    create(:enrollment, user: friend, course: course)
  end

  after { Flipper.disable(FlipperFlags::FRIENDS_AVAILABILITY_ONLY) }

  def enable_flag(user = viewer)
    Flipper.enable_actor(FlipperFlags::FRIENDS_AVAILABILITY_ONLY, user)
  end

  def json = response.parsed_body

  describe "POST /api/friends/:friend_id/processed_events" do
    it "sends the course list while the friend shares the full schedule" do
      post "/api/friends/#{friend.public_id}/processed_events", params: { term_uid: term.uid }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json["classes"].first["title"]).to eq("Secret Topology Seminar")
    end

    it "answers 403 with no course data when the friend shares only availability" do
      friendship.update_visibility_for!(friend, :availability_only)

      post "/api/friends/#{friend.public_id}/processed_events", params: { term_uid: term.uid }, headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq(
        "error" => "This friend shares only availability", "code" => "AVAILABILITY_ONLY", "visibility" => "availability_only"
      )
    end

    it "answers 403 while the flag is off, so a saved level stays in force" do
      friendship.update_visibility_for!(friend, :availability_only)

      post "/api/friends/#{friend.public_id}/processed_events", params: { term_uid: term.uid }, headers: headers

      expect(response).to have_http_status(:forbidden)
    end

    it "uses the friend's level, not the viewer's own level" do
      friendship.update_visibility_for!(viewer, :availability_only)

      post "/api/friends/#{friend.public_id}/processed_events", params: { term_uid: term.uid }, headers: headers
      expect(response).to have_http_status(:ok)

      post "/api/friends/#{viewer.public_id}/processed_events",
           params: { term_uid: term.uid }, headers: auth_headers_for(friend)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/friends/:friend_id/processed_events for a user who is not a friend" do
    it "answers 403 with the code NOT_FRIENDS" do
      stranger = create(:user)

      post "/api/friends/#{stranger.public_id}/processed_events", params: { term_uid: term.uid }, headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "You are not friends with this user", "code" => "NOT_FRIENDS")
    end
  end

  describe "POST /api/friends/:friend_id/is_processed" do
    it "answers for a friend who shares the full schedule" do
      post "/api/friends/#{friend.public_id}/is_processed", params: { term_uid: term.uid }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("processed" => true)
    end

    it "answers 403 AVAILABILITY_ONLY when the friend shares only availability" do
      friendship.update_visibility_for!(friend, :availability_only)

      post "/api/friends/#{friend.public_id}/is_processed", params: { term_uid: term.uid }, headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq(
        "error" => "This friend shares only availability", "code" => "AVAILABILITY_ONLY", "visibility" => "availability_only"
      )
    end

    it "answers 403 NOT_FRIENDS for a user who is not a friend" do
      post "/api/friends/#{create(:user).public_id}/is_processed", params: { term_uid: term.uid }, headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(json["code"]).to eq("NOT_FRIENDS")
    end
  end

  describe "GET /api/friends/:friend_id/busy_blocks" do
    let(:params) { { start_date: "2026-10-05", end_date: "2026-10-11" } }

    it "answers 404 while the flag is off and the friend shares the full schedule" do
      get "/api/friends/#{friend.public_id}/busy_blocks", params: params, headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "answers 200 while the viewer's flag is off and the friend shares only availability" do
      friendship.update_visibility_for!(friend, :availability_only)

      get "/api/friends/#{friend.public_id}/busy_blocks", params: params, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json["busy"].length).to eq(1)
    end

    it "answers 403 NOT_FRIENDS for a user who is not a friend, with the flag off" do
      get "/api/friends/#{create(:user).public_id}/busy_blocks", params: params, headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(json["code"]).to eq("NOT_FRIENDS")
    end

    context "with the flag on" do
      before do
        enable_flag
        friendship.update_visibility_for!(friend, :availability_only)
      end

      it "sends only dates and times" do
        get "/api/friends/#{friend.public_id}/busy_blocks", params: params, headers: headers

        expect(response).to have_http_status(:ok)
        expect(json).to eq(
          "time_zone"  => "America/New_York",
          "start_date" => "2026-10-05",
          "end_date"   => "2026-10-11",
          "busy"       => [ { "date" => "2026-10-05", "weekday" => "monday", "start" => "09:00", "end" => "10:15" } ]
        )
      end

      it "sends no course data" do
        get "/api/friends/#{friend.public_id}/busy_blocks", params: params, headers: headers

        body = response.body
        [
          "Secret Topology Seminar", "98765", "QXZY", "4321", "Zyxwv Hall", "ZYXQ", "777",
          "Quillon", "Vexmarch", "qvexmarch", course.public_id, meeting_time.public_id,
          term.public_id, "classes", "title", "professor", "location", "calendar_config"
        ].each do |secret|
          expect(body).not_to include(secret.to_s)
        end
      end

      it "works for a friend who shares the full schedule too" do
        friendship.update_visibility_for!(friend, :full)

        get "/api/friends/#{friend.public_id}/busy_blocks", params: params, headers: headers

        expect(response).to have_http_status(:ok)
        expect(json["busy"].length).to eq(1)
      end

      it "defaults to the seven days from today" do
        travel_to Time.zone.local(2026, 10, 5, 12) do
          get "/api/friends/#{friend.public_id}/busy_blocks", headers: headers
        end

        expect(json.values_at("start_date", "end_date")).to eq(%w[2026-10-05 2026-10-11])
      end

      it "refuses a user who is not a friend" do
        stranger = create(:user)

        get "/api/friends/#{stranger.public_id}/busy_blocks", params: params, headers: headers

        expect(response).to have_http_status(:forbidden)
        expect(json["code"]).to eq("NOT_FRIENDS")
        expect(response.body).not_to include("busy")
      end

      it "refuses a pending request" do
        other = create(:user)
        create(:friendship, requester: viewer, addressee: other)

        get "/api/friends/#{other.public_id}/busy_blocks", params: params, headers: headers

        expect(response).to have_http_status(:forbidden)
      end

      it "refuses a date that is not YYYY-MM-DD" do
        get "/api/friends/#{friend.public_id}/busy_blocks", params: { start_date: "10/05/2026" }, headers: headers

        expect(response).to have_http_status(:bad_request)
      end

      it "refuses an end date before the start date" do
        get "/api/friends/#{friend.public_id}/busy_blocks",
            params: { start_date: "2026-10-11", end_date: "2026-10-05" }, headers: headers

        expect(response).to have_http_status(:bad_request)
      end

      it "refuses a range longer than the limit" do
        get "/api/friends/#{friend.public_id}/busy_blocks",
            params: { start_date: "2026-01-01", end_date: "2026-12-31" }, headers: headers

        expect(response).to have_http_status(:bad_request)
      end

      it "reads the course meeting times in one query, however many classes there are" do
        2.times do
          other = create(:course, term: term)
          create(:course_meeting_time, course: other, day_of_week: :tuesday)
          create(:enrollment, user: friend, course: other)
        end

        count = 0
        counter = ->(*, payload) { count += 1 if payload[:sql].include?("course_meeting_times") && !payload[:cached] }
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          get "/api/friends/#{friend.public_id}/busy_blocks", params: params, headers: headers
        end

        expect(response).to have_http_status(:ok)
        expect(count).to eq(1)
      end
    end
  end

  describe "GET /api/friends" do
    def listed_friend = json["friends"].find { |row| row["id"] == friend.public_id }

    it "sends both levels for each friend while the flag is on" do
      enable_flag
      friendship.update_visibility_for!(viewer, :availability_only)

      get "/api/friends", headers: headers

      expect(response).to have_http_status(:ok)
      expect(listed_friend["visibility"]).to eq("mine" => "availability_only", "theirs" => "full")
    end

    it "sends both levels while the flag is off and the friend shares only availability" do
      friendship.update_visibility_for!(friend, :availability_only)

      get "/api/friends", headers: headers

      expect(listed_friend["visibility"]).to eq("mine" => "full", "theirs" => "availability_only")
    end

    it "sends a null visibility while the flag is off and the friend shares the full schedule" do
      get "/api/friends", headers: headers

      expect(listed_friend).to include("name" => friend.full_name, "visibility" => nil)
    end

    it "lists only accepted friends" do
      create(:friendship, requester: create(:user), addressee: viewer)

      get "/api/friends", headers: headers

      expect(json["friends"].pluck("id")).to eq([ friend.public_id ])
    end
  end

  describe "GET /api/friends/:friend_id/visibility" do
    it "answers 404 while the flag is off" do
      get "/api/friends/#{friend.public_id}/visibility", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "answers 200 while the viewer's flag is off and the friend shares only availability" do
      friendship.update_visibility_for!(friend, :availability_only)

      get "/api/friends/#{friend.public_id}/visibility", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("friend_id" => friend.public_id, "mine" => "full", "theirs" => "availability_only")
    end

    it "sends both levels as seen by the viewer" do
      enable_flag
      friendship.update_visibility_for!(friend, :availability_only)

      get "/api/friends/#{friend.public_id}/visibility", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("friend_id" => friend.public_id, "mine" => "full", "theirs" => "availability_only")
    end
  end

  describe "PATCH /api/friends/:friend_id/visibility" do
    it "answers 404 while the flag is off and changes nothing" do
      patch "/api/friends/#{friend.public_id}/visibility", params: { visibility: "availability_only" }, headers: headers

      expect(response).to have_http_status(:not_found)
      expect(friendship.reload).to be_requester_full
    end

    context "with the flag on" do
      before { enable_flag }

      it "sets the viewer's own level only" do
        patch "/api/friends/#{friend.public_id}/visibility", params: { visibility: "availability_only" }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(json).to eq("friend_id" => friend.public_id, "mine" => "availability_only", "theirs" => "full")
        expect(friendship.reload).to be_requester_availability_only
        expect(friendship).to be_addressee_full
      end

      it "sets the addressee's column when the addressee asks" do
        enable_flag(friend)

        patch "/api/friends/#{viewer.public_id}/visibility",
              params: { visibility: "availability_only" }, headers: auth_headers_for(friend)

        expect(response).to have_http_status(:ok)
        expect(friendship.reload).to be_addressee_availability_only
        expect(friendship).to be_requester_full
      end

      it "refuses an unknown level" do
        patch "/api/friends/#{friend.public_id}/visibility", params: { visibility: "hidden" }, headers: headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(friendship.reload).to be_requester_full
      end

      it "refuses a missing level" do
        patch "/api/friends/#{friend.public_id}/visibility", headers: headers

        expect(response).to have_http_status(:bad_request)
      end

      it "refuses a user who is not a friend" do
        patch "/api/friends/#{create(:user).public_id}/visibility",
              params: { visibility: "availability_only" }, headers: headers

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /api/user/busy_blocks" do
    let(:params) { { start_date: "2026-10-05", end_date: "2026-10-11" } }

    before do
      create(:enrollment, user: viewer, course: course)
      create(:university_calendar_event, category: "holiday", summary: "Holiday",
                                         start_time: Time.zone.local(2026, 10, 12), end_time: Time.zone.local(2026, 10, 12, 23))
    end

    it "sends the busy blocks of the signed-in user, with no flag" do
      get "/api/user/busy_blocks", params: params, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json["busy"]).to eq([ { "date" => "2026-10-05", "weekday" => "monday", "start" => "09:00", "end" => "10:15" } ])
    end

    it "removes a no-class day" do
      get "/api/user/busy_blocks", params: { start_date: "2026-10-12", end_date: "2026-10-12" }, headers: headers

      expect(json["busy"]).to eq([])
    end

    it "refuses a date that is not YYYY-MM-DD" do
      get "/api/user/busy_blocks", params: { start_date: "nope" }, headers: headers

      expect(response).to have_http_status(:bad_request)
    end

    it "needs a token" do
      get "/api/user/busy_blocks", params: params

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/friends/requests with a visibility" do
    let(:other) { create(:user) }

    it "starts the sender's own side at the chosen level when the flag is on" do
      enable_flag
      post "/api/friends/requests", params: { friend_id: other.public_id, visibility: "availability_only" }, headers: headers

      expect(response).to have_http_status(:created)
      created = Friendship.find_by!(requester: viewer, addressee: other)
      expect(created).to be_requester_availability_only
      expect(created).to be_addressee_full
    end

    it "defaults to full with no param" do
      post "/api/friends/requests", params: { friend_id: other.public_id }, headers: headers

      expect(Friendship.find_by!(requester: viewer, addressee: other)).to be_requester_full
    end

    it "answers 404 and creates nothing while the flag is off" do
      expect {
        post "/api/friends/requests", params: { friend_id: other.public_id, visibility: "availability_only" }, headers: headers
      }.not_to change(Friendship, :count)

      expect(response).to have_http_status(:not_found)
    end

    it "refuses an unknown level" do
      enable_flag

      expect {
        post "/api/friends/requests", params: { friend_id: other.public_id, visibility: "hidden" }, headers: headers
      }.not_to change(Friendship, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /api/friends/requests/:request_id/accept with a visibility" do
    let(:other)   { create(:user) }
    let!(:pending) { create(:friendship, requester: other, addressee: viewer) }

    it "sets only the accepting user's own side when the flag is on" do
      enable_flag
      post "/api/friends/requests/#{pending.public_id}/accept", params: { visibility: "availability_only" }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(pending.reload).to be_accepted
      expect(pending).to be_addressee_availability_only
      expect(pending).to be_requester_full
    end

    it "defaults to full with no param" do
      post "/api/friends/requests/#{pending.public_id}/accept", headers: headers

      expect(pending.reload).to be_addressee_full
    end

    it "answers 404 and leaves the request pending while the flag is off" do
      post "/api/friends/requests/#{pending.public_id}/accept", params: { visibility: "availability_only" }, headers: headers

      expect(response).to have_http_status(:not_found)
      expect(pending.reload).to be_pending
    end

    it "refuses an unknown level and leaves the request pending" do
      enable_flag
      post "/api/friends/requests/#{pending.public_id}/accept", params: { visibility: "hidden" }, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(pending.reload).to be_pending
    end
  end
end
