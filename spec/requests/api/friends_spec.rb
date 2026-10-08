# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Friends", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user)    { create(:user, first_name: "Ada", last_name: "Lovelace") }
  let(:friend)  { create(:user, first_name: "Grace", last_name: "Hopper") }
  let(:headers) { auth_headers_for(user) }
  let(:body)    { response.parsed_body }

  after { Flipper.disable(FlipperFlags::FRIEND_EXPIRY) }

  def enable_friend_expiry(actor = user)
    Flipper.enable_actor(FlipperFlags::FRIEND_EXPIRY, actor)
  end

  describe "GET /api/friends" do
    it "lists each friend with the expiry date, or null for a permanent friend" do
      expires_at = 10.days.from_now.change(usec: 0)
      other      = create(:user, first_name: "Alan", last_name: "Turing")
      create(:friendship, :accepted, requester: user, addressee: friend, expires_at: expires_at)
      create(:friendship, :accepted, requester: other, addressee: user)

      get "/api/friends", headers: headers

      expect(response).to have_http_status(:ok)
      expect(body["friends"]).to contain_exactly(
        { "id" => friend.public_id, "name" => "Grace Hopper", "visibility" => nil,
          "expires_at" => expires_at.iso8601, "expiry_proposal" => nil },
        { "id" => other.public_id,  "name" => "Alan Turing", "visibility" => nil,
          "expires_at" => nil, "expiry_proposal" => nil }
      )
    end

    it "leaves out a friend after the expiry date" do
      create(:friendship, :accepted, :temporary, requester: user, addressee: friend)

      travel 8.days do
        get "/api/friends", headers: auth_headers_for(user)

        expect(response).to have_http_status(:ok)
        expect(body["friends"]).to be_empty
      end
    end
  end

  describe "GET /api/friends/requests" do
    it "gives the expiry date on incoming and outgoing requests" do
      expires_at = 10.days.from_now.change(usec: 0)
      incoming   = create(:friendship, requester: friend, addressee: user, expires_at: expires_at)
      stranger   = create(:user, first_name: "Alan", last_name: "Turing")
      outgoing   = create(:friendship, requester: user, addressee: stranger)

      get "/api/friends/requests", headers: headers

      expect(body["incoming"]).to eq([
        {
          "request_id" => incoming.public_id,
          "from"       => { "id" => friend.public_id, "name" => "Grace Hopper" },
          "created_at"      => incoming.created_at.iso8601,
          "expires_at"      => expires_at.iso8601,
          "expiry_proposal" => nil
        }
      ])
      expect(body["outgoing"]).to eq([
        {
          "request_id" => outgoing.public_id,
          "to"         => { "id" => stranger.public_id, "name" => "Alan Turing" },
          "created_at"      => outgoing.created_at.iso8601,
          "expires_at"      => nil,
          "expiry_proposal" => nil
        }
      ])
    end

    it "leaves out an expired request" do
      create(:friendship, :temporary, requester: friend, addressee: user)

      travel 8.days do
        get "/api/friends/requests", headers: auth_headers_for(user)

        expect(response).to have_http_status(:ok)
        expect(body["incoming"]).to be_empty
      end
    end
  end

  describe "POST /api/friends/requests" do
    it "sends a permanent request without expires_at, with the flag off" do
      post "/api/friends/requests", params: { friend_id: friend.public_id }, headers: headers

      expect(response).to have_http_status(:created)
      expect(body["expires_at"]).to be_nil
      expect(Friendship.last.expires_at).to be_nil
    end

    it "refuses expires_at while the flag is off, and creates nothing" do
      expect {
        post "/api/friends/requests",
             params: { friend_id: friend.public_id, expires_at: 10.days.from_now.iso8601 }, headers: headers
      }.not_to change(Friendship, :count)

      expect(response).to have_http_status(:not_found)
      expect(body["error"]).to eq("Temporary friendships are not enabled")
    end

    context "with the flag on" do
      before { enable_friend_expiry }

      it "stores the expiry date" do
        expires_at = 10.days.from_now.change(usec: 0)

        post "/api/friends/requests",
             params: { friend_id: friend.public_id, expires_at: expires_at.iso8601 }, headers: headers

        expect(response).to have_http_status(:created)
        expect(body["expires_at"]).to eq(expires_at.iso8601)
        expect(Friendship.last.expires_at).to eq(expires_at)
      end

      it "reads a date with no time as the end of that day in New York" do
        post "/api/friends/requests",
             params: { friend_id: friend.public_id, expires_at: "2099-12-01" }, headers: headers

        expect(response).to have_http_status(:created)
        expect(Friendship.last.expires_at).to eq(ActiveSupport::TimeZone["America/New_York"].local(2099, 12, 1, 23, 59, 59))
      end

      it "answers 400 for a time with no UTC offset" do
        post "/api/friends/requests",
             params: { friend_id: friend.public_id, expires_at: "2099-12-01T12:00:00" }, headers: headers

        expect(response).to have_http_status(:bad_request)
        expect(body["error"]).to include("UTC offset")
        expect(Friendship.count).to eq(0)
      end

      it "answers 400 for a value that is not a time" do
        post "/api/friends/requests",
             params: { friend_id: friend.public_id, expires_at: "next tuesday" }, headers: headers

        expect(response).to have_http_status(:bad_request)
        expect(Friendship.count).to eq(0)
      end

      it "answers 422 for a time in the past" do
        post "/api/friends/requests",
             params: { friend_id: friend.public_id, expires_at: 1.day.ago.iso8601 }, headers: headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(body["error"]).to eq("Expires at must be in the future")
      end

      it "accepts a new request after an old friendship expired" do
        create(:friendship, :accepted, :temporary, requester: friend, addressee: user)

        travel 8.days do
          post "/api/friends/requests", params: { friend_id: friend.public_id }, headers: auth_headers_for(user)

          expect(response).to have_http_status(:created)
          expect(Friendship.count).to eq(1)
        end
      end
    end
  end

  describe "POST /api/friends/requests/:request_id/accept" do
    it "gives the expiry date in the response" do
      expires_at = 10.days.from_now.change(usec: 0)
      request = create(:friendship, requester: friend, addressee: user, expires_at: expires_at)

      post "/api/friends/requests/#{request.public_id}/accept", headers: headers

      expect(response).to have_http_status(:ok)
      expect(body["expires_at"]).to eq(expires_at.iso8601)
    end

    it "answers with the serializer shape and the prefixed friend id" do
      request = create(:friendship, requester: friend, addressee: user)

      post "/api/friends/requests/#{request.public_id}/accept", headers: headers

      expect(body).to eq(
        "friendship_id"   => request.public_id,
        "status"          => "accepted",
        "expires_at"      => nil,
        "expiry_proposal" => nil,
        "friend"          => { "id" => friend.public_id, "name" => "Grace Hopper" }
      )
      expect(body.dig("friend", "id")).to start_with("usr_")
    end

    it "refuses an expired request" do
      request = create(:friendship, :temporary, requester: friend, addressee: user)

      travel 8.days do
        post "/api/friends/requests/#{request.public_id}/accept", headers: auth_headers_for(user)

        expect(response).to have_http_status(:forbidden)
        expect(request.reload).to be_pending
      end
    end
  end

  describe "PATCH /api/friends/:friend_id/expiry" do
    let!(:friendship) { create(:friendship, :accepted, :temporary, requester: friend, addressee: user) }

    it "answers 404 while the flag is off, and changes nothing" do
      patch "/api/friends/#{friend.public_id}/expiry", params: { expires_at: nil }, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(friendship.reload.expires_at).to be_present
    end

    context "with the flag on" do
      before { enable_friend_expiry }

      it "only proposes a later date, and keeps the current one" do
        current    = friendship.expires_at
        expires_at = 60.days.from_now.change(usec: 0)

        patch "/api/friends/#{friend.public_id}/expiry",
              params: { expires_at: expires_at.iso8601 }, headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(body).to eq(
          "friendship_id"   => friendship.public_id,
          "status"          => "accepted",
          "expires_at"      => current.iso8601,
          "expiry_proposal" => {
            "expires_at" => expires_at.iso8601, "permanent" => false,
            "proposed_by" => user.public_id, "can_accept" => false
          },
          "friend"          => { "id" => friend.public_id, "name" => "Grace Hopper" },
          "expiry_change"   => "proposed"
        )
        expect(friendship.reload.expires_at).to eq(current)
      end

      it "does not make a one-week friendship permanent alone, but proposes it" do
        patch "/api/friends/#{friend.public_id}/expiry", params: { expires_at: nil }, headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(body["expiry_change"]).to eq("proposed")
        expect(body["expires_at"]).to be_present
        expect(body["expiry_proposal"]).to include("permanent" => true, "expires_at" => nil)
        expect(friendship.reload.expires_at).to be_present
      end

      it "applies a sooner date at once and clears an open proposal" do
        friendship.change_expiry!(to: nil, by: friend)

        patch "/api/friends/#{friend.public_id}/expiry",
              params: { expires_at: 3.days.from_now.to_date.iso8601 }, headers: headers, as: :json

        expect(body["expiry_change"]).to eq("shortened")
        expect(body["expiry_proposal"]).to be_nil
        expect(friendship.reload.expires_at).to eq(3.days.from_now.to_date.in_time_zone("America/New_York").end_of_day.change(usec: 0))
      end

      it "answers unchanged for the same date" do
        patch "/api/friends/#{friend.public_id}/expiry",
              params: { expires_at: friendship.expires_at.iso8601 }, headers: headers, as: :json

        expect(body["expiry_change"]).to eq("unchanged")
      end

      it "answers 400 for a time with no UTC offset" do
        patch "/api/friends/#{friend.public_id}/expiry",
              params: { expires_at: 3.days.from_now.strftime("%Y-%m-%dT%H:%M:%S") }, headers: headers, as: :json

        expect(response).to have_http_status(:bad_request)
      end

      it "lets the requester change a pending request too" do
        stranger = create(:user)
        request  = create(:friendship, requester: user, addressee: stranger)

        patch "/api/friends/#{stranger.public_id}/expiry",
              params: { expires_at: 5.days.from_now.iso8601 }, headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(body["status"]).to eq("pending")
        expect(body["expiry_change"]).to eq("shortened")
        expect(request.reload.expires_at).to be_present
      end

      it "answers 400 without expires_at" do
        patch "/api/friends/#{friend.public_id}/expiry", params: {}, headers: headers, as: :json

        expect(response).to have_http_status(:bad_request)
      end

      it "answers 422 for a time in the past" do
        patch "/api/friends/#{friend.public_id}/expiry",
              params: { expires_at: 1.day.ago.iso8601 }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "answers 404 for a user who is not a friend" do
        patch "/api/friends/#{create(:user).public_id}/expiry",
              params: { expires_at: nil }, headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end

      it "answers 404 after the expiry date, so an ended friendship cannot come back" do
        travel 8.days do
          patch "/api/friends/#{friend.public_id}/expiry",
                params: { expires_at: nil }, headers: auth_headers_for(user), as: :json

          expect(response).to have_http_status(:not_found)
        end
      end
    end
  end

  describe "POST /api/friends/:friend_id/expiry/accept and /decline" do
    let!(:friendship) { create(:friendship, :accepted, :temporary, requester: friend, addressee: user) }

    it "answers 404 while the flag is off" do
      friendship.change_expiry!(to: nil, by: friend)

      post "/api/friends/#{friend.public_id}/expiry/accept", headers: headers
      expect(response).to have_http_status(:not_found)

      post "/api/friends/#{friend.public_id}/expiry/decline", headers: headers
      expect(response).to have_http_status(:not_found)
      expect(friendship.reload.expiry_proposal?).to be(true)
    end

    context "with the flag on" do
      before do
        enable_friend_expiry(user)
        enable_friend_expiry(friend)
      end

      it "lets the other user accept a permanent proposal" do
        friendship.change_expiry!(to: nil, by: friend)

        post "/api/friends/#{friend.public_id}/expiry/accept", headers: headers

        expect(response).to have_http_status(:ok)
        expect(body["expires_at"]).to be_nil
        expect(body["expiry_proposal"]).to be_nil
        expect(friendship.reload.expires_at).to be_nil
      end

      it "shows can_accept to the other user" do
        friendship.change_expiry!(to: nil, by: friend)

        get "/api/friends", headers: headers

        expect(body["friends"].first["expiry_proposal"]).to include("proposed_by" => friend.public_id, "can_accept" => true)
      end

      it "refuses the proposer with 403" do
        friendship.change_expiry!(to: nil, by: user)

        post "/api/friends/#{friend.public_id}/expiry/accept", headers: headers

        expect(response).to have_http_status(:forbidden)
        expect(friendship.reload.expires_at).to be_present
      end

      it "refuses with 403 when there is no proposal" do
        post "/api/friends/#{friend.public_id}/expiry/accept", headers: headers

        expect(response).to have_http_status(:forbidden)
      end

      it "lets the other user decline, and keeps the date" do
        friendship.change_expiry!(to: nil, by: friend)

        post "/api/friends/#{friend.public_id}/expiry/decline", headers: headers

        expect(response).to have_http_status(:ok)
        expect(body["expiry_proposal"]).to be_nil
        expect(friendship.reload.expires_at).to be_present
      end

      it "lets the proposer withdraw the proposal" do
        friendship.change_expiry!(to: nil, by: user)

        post "/api/friends/#{friend.public_id}/expiry/decline", headers: headers

        expect(response).to have_http_status(:ok)
        expect(friendship.reload.expiry_proposal?).to be(false)
      end

      it "lets the requester accept the addressee's counter-proposal on a pending request" do
        stranger = create(:user)
        request  = create(:friendship, :temporary, requester: user, addressee: stranger)
        request.change_expiry!(to: nil, by: stranger)

        post "/api/friends/#{stranger.public_id}/expiry/accept", headers: headers

        expect(response).to have_http_status(:ok)
        expect(body["status"]).to eq("pending")
        expect(request.reload.expires_at).to be_nil
      end

      it "answers 404 for a user with no friendship" do
        post "/api/friends/#{create(:user).public_id}/expiry/accept", headers: headers

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "schedule access after expiry" do
    let!(:term) { create(:term) }

    before { create(:friendship, :accepted, :temporary, requester: user, addressee: friend) }

    it "shows the friend's schedule before the expiry date" do
      post "/api/friends/#{friend.public_id}/processed_events", params: { term_uid: term.uid }, headers: headers

      expect(response).to have_http_status(:ok)
    end

    it "refuses processed_events and is_processed after the expiry date" do
      travel 8.days do
        auth = auth_headers_for(user)

        post "/api/friends/#{friend.public_id}/processed_events", params: { term_uid: term.uid }, headers: auth
        expect(response).to have_http_status(:forbidden)

        post "/api/friends/#{friend.public_id}/is_processed", params: { term_uid: term.uid }, headers: auth
        expect(response).to have_http_status(:forbidden)
      end
    end

    it "does not unfriend an expired friendship, because it no longer exists for the user" do
      travel 8.days do
        delete "/api/friends/#{friend.public_id}", headers: auth_headers_for(user)

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
