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
        { "id" => friend.public_id, "name" => "Grace Hopper", "expires_at" => expires_at.iso8601 },
        { "id" => other.public_id,  "name" => "Alan Turing",  "expires_at" => nil }
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
          "created_at" => incoming.created_at.iso8601,
          "expires_at" => expires_at.iso8601
        }
      ])
      expect(body["outgoing"]).to eq([
        {
          "request_id" => outgoing.public_id,
          "to"         => { "id" => stranger.public_id, "name" => "Alan Turing" },
          "created_at" => outgoing.created_at.iso8601,
          "expires_at" => nil
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

      it "extends the expiry date" do
        expires_at = 60.days.from_now.change(usec: 0)

        patch "/api/friends/#{friend.public_id}/expiry",
              params: { expires_at: expires_at.iso8601 }, headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(body).to eq(
          "friendship_id" => friendship.public_id,
          "status"        => "accepted",
          "expires_at"    => expires_at.iso8601,
          "friend"        => { "id" => friend.public_id, "name" => "Grace Hopper" }
        )
        expect(friendship.reload.expires_at).to eq(expires_at)
      end

      it "makes the friendship permanent with null" do
        patch "/api/friends/#{friend.public_id}/expiry", params: { expires_at: nil }, headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(body["expires_at"]).to be_nil
        expect(friendship.reload.expires_at).to be_nil
      end

      it "lets the requester change a pending request too" do
        stranger = create(:user)
        request  = create(:friendship, requester: user, addressee: stranger)

        patch "/api/friends/#{stranger.public_id}/expiry",
              params: { expires_at: 5.days.from_now.iso8601 }, headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(body["status"]).to eq("pending")
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
