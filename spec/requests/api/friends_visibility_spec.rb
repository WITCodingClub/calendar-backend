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

  describe "GET /api/friends/:friend_id/busy_blocks" do
    let(:params) { { start_date: "2026-10-05", end_date: "2026-10-11" } }

    it "answers 404 while the flag is off" do
      get "/api/friends/#{friend.public_id}/busy_blocks", params: params, headers: headers

      expect(response).to have_http_status(:not_found)
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

  describe "GET /api/friends/:friend_id/visibility" do
    it "answers 404 while the flag is off" do
      get "/api/friends/#{friend.public_id}/visibility", headers: headers

      expect(response).to have_http_status(:not_found)
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
end
