# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Friends" do
  let(:user) { create(:user) }
  let(:jwt_token) { JsonWebTokenService.encode(user_id: user.id) }
  let(:headers) { { "Authorization" => "Bearer #{jwt_token}", "Content-Type" => "application/json" } }

  before do
    Flipper.enable(FlipperFlags::V1, user)
  end

  describe "GET /api/friends" do
    let!(:friend1) { create(:user, first_name: "Alice", last_name: "Smith") }
    let!(:friend2) { create(:user, first_name: "Bob", last_name: "Jones") }

    before do
      create(:friendship, :accepted, requester: user, addressee: friend1)
      create(:friendship, :accepted, requester: friend2, addressee: user)
      # Pending request should not appear
      create(:friendship, :pending, requester: user, addressee: create(:user))
    end

    it "returns accepted friends" do
      get "/api/friends", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body

      expect(json["friends"].length).to eq(2)
      expect(json["friends"].pluck("name")).to contain_exactly("Alice Smith", "Bob Jones")
    end
  end

  describe "GET /api/friends/requests" do
    let!(:incoming_requester) { create(:user, first_name: "Incoming", last_name: "User") }
    let!(:outgoing_addressee) { create(:user, first_name: "Outgoing", last_name: "User") }

    before do
      create(:friendship, :pending, requester: incoming_requester, addressee: user)
      create(:friendship, :pending, requester: user, addressee: outgoing_addressee)
    end

    it "returns incoming and outgoing requests" do
      get "/api/friends/requests", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body

      expect(json["incoming"].length).to eq(1)
      expect(json["incoming"][0]["from"]["name"]).to eq("Incoming User")

      expect(json["outgoing"].length).to eq(1)
      expect(json["outgoing"][0]["to"]["name"]).to eq("Outgoing User")
    end
  end

  describe "POST /api/friends/requests" do
    let(:target_user) { create(:user) }

    it "creates a friend request" do
      post "/api/friends/requests",
           params: { friend_id: target_user.public_id }.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      json = response.parsed_body

      expect(json["request_id"]).to start_with("frn_")
      expect(Friendship.pending.exists?(requester: user, addressee: target_user)).to be true
    end

    it "prevents duplicate requests" do
      create(:friendship, requester: user, addressee: target_user)

      post "/api/friends/requests",
           params: { friend_id: target_user.public_id }.to_json,
           headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "prevents self-friending" do
      post "/api/friends/requests",
           params: { friend_id: user.public_id }.to_json,
           headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /api/friends/requests/:request_id/accept" do
    let(:requester) { create(:user, first_name: "Requester", last_name: "User") }
    let!(:friendship) { create(:friendship, :pending, requester: requester, addressee: user) }

    it "accepts the friend request" do
      post "/api/friends/requests/#{friendship.public_id}/accept", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body

      expect(json["friendship_id"]).to eq(friendship.public_id)
      expect(json["friend"]["name"]).to eq("Requester User")
      expect(friendship.reload).to be_accepted
    end

    it "denies non-addressee from accepting" do
      other_user = create(:user)
      other_headers = {
        "Authorization" => "Bearer #{JsonWebTokenService.encode(user_id: other_user.id)}",
        "Content-Type"  => "application/json"
      }
      Flipper.enable(FlipperFlags::V1, other_user)

      post "/api/friends/requests/#{friendship.public_id}/accept", headers: other_headers

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/friends/requests/:request_id/decline" do
    let(:requester) { create(:user) }
    let!(:friendship) { create(:friendship, :pending, requester: requester, addressee: user) }

    it "declines and deletes the request" do
      post "/api/friends/requests/#{friendship.public_id}/decline", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["ok"]).to be true
      expect(Friendship.exists?(friendship.id)).to be false
    end
  end

  describe "DELETE /api/friends/requests/:request_id" do
    let(:addressee) { create(:user) }
    let!(:friendship) { create(:friendship, :pending, requester: user, addressee: addressee) }

    it "cancels outgoing request" do
      delete "/api/friends/requests/#{friendship.public_id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(Friendship.exists?(friendship.id)).to be false
    end

    it "denies addressee from canceling" do
      other_headers = {
        "Authorization" => "Bearer #{JsonWebTokenService.encode(user_id: addressee.id)}",
        "Content-Type"  => "application/json"
      }
      Flipper.enable(FlipperFlags::V1, addressee)

      delete "/api/friends/requests/#{friendship.public_id}", headers: other_headers

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "DELETE /api/friends/:friend_id" do
    let(:friend) { create(:user) }

    before do
      create(:friendship, :accepted, requester: user, addressee: friend)
    end

    it "unfriends the user" do
      delete "/api/friends/#{friend.public_id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(user.friend_of?(friend)).to be false
    end

    it "returns 404 if not friends" do
      stranger = create(:user)

      delete "/api/friends/#{stranger.public_id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/friends/:friend_id/processed_events" do
    let(:friend) { create(:user) }
    let(:term) { create(:term) }

    before do
      create(:friendship, :accepted, requester: user, addressee: friend)
      # Create enrollment for friend
      course = create(:course, term: term)
      create(:enrollment, user: friend, course: course, term: term)
    end

    it "returns friend's schedule" do
      post "/api/friends/#{friend.public_id}/processed_events",
           params: { term_uid: term.uid }.to_json,
           headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body

      expect(json["classes"]).to be_present
    end

    it "denies access to non-friends" do
      stranger = create(:user)

      post "/api/friends/#{stranger.public_id}/processed_events",
           params: { term_uid: term.uid }.to_json,
           headers: headers

      expect(response).to have_http_status(:forbidden)
    end

    it "requires term_uid" do
      post "/api/friends/#{friend.public_id}/processed_events",
           params: {}.to_json,
           headers: headers

      expect(response).to have_http_status(:bad_request)
    end

    it "returns 404 for unknown term" do
      post "/api/friends/#{friend.public_id}/processed_events",
           params: { term_uid: 999999 }.to_json,
           headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/friends/:friend_id/is_processed" do
    let(:friend) { create(:user) }
    let(:term) { create(:term) }

    before do
      create(:friendship, :accepted, requester: user, addressee: friend)
    end

    context "when friend has courses" do
      before do
        course = create(:course, term: term)
        create(:enrollment, user: friend, course: course, term: term)
      end

      it "returns processed: true" do
        post "/api/friends/#{friend.public_id}/is_processed",
             params: { term_uid: term.uid }.to_json,
             headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["processed"]).to be true
      end
    end

    context "when friend has no courses" do
      it "returns processed: false" do
        post "/api/friends/#{friend.public_id}/is_processed",
             params: { term_uid: term.uid }.to_json,
             headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["processed"]).to be false
      end
    end

    it "denies access to non-friends" do
      stranger = create(:user)

      post "/api/friends/#{stranger.public_id}/is_processed",
           params: { term_uid: term.uid }.to_json,
           headers: headers

      expect(response).to have_http_status(:forbidden)
    end
  end
end
