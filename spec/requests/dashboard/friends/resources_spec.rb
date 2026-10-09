# frozen_string_literal: true

require "rails_helper"

# The requests, visibility, expiry, and expiry proposal resources under
# /dashboard/friends. friends_spec.rb covers what each action does. This file
# covers access to a friendship between two other users, and the old paths.
RSpec.describe "Dashboard::Friends resources", type: :request do
  let(:current_user) { create(:user, :with_processed_courses, first_name: "Ada") }
  let(:grace)        { create(:user, first_name: "Grace") }
  let(:alan)         { create(:user, first_name: "Alan") }

  before { sign_in current_user }

  after do
    Flipper.disable(FeatureFlags::FRIEND_EXPIRY)
    Flipper.disable(FeatureFlags::FRIENDS_AVAILABILITY_ONLY)
  end

  describe "GET /dashboard/friends/requests" do
    # FriendshipMailer and the extension (FriendshipSerializer#review_url) link
    # to this exact path, so it must not change.
    it "keeps the path that the emails link to" do
      expect(dashboard_friends_requests_path).to eq("/dashboard/friends/requests")

      get "/dashboard/friends/requests"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Friend Requests")
    end

    it "does not list a request between two other users" do
      create(:friendship, requester: grace, addressee: alan)

      get dashboard_friends_requests_path

      expect(response.body).not_to include(grace.email)
      expect(response.body).to include("No incoming requests.")
    end
  end

  describe "PATCH /dashboard/friends/requests/:id" do
    it "does not accept a request between two other users" do
      request = create(:friendship, requester: grace, addressee: alan)

      patch dashboard_friends_request_path(request.id)

      expect(flash[:alert]).to eq("Request not found.")
      expect(request.reload).to be_pending
    end

    it "does not let the requester accept their own request" do
      request = create(:friendship, requester: current_user, addressee: grace)

      patch dashboard_friends_request_path(request.id)

      expect(flash[:alert]).to eq("Request not found.")
      expect(request.reload).to be_pending
    end
  end

  describe "DELETE /dashboard/friends/requests/:id" do
    it "does not decline a request between two other users" do
      request = create(:friendship, requester: grace, addressee: alan)

      expect { delete dashboard_friends_request_path(request.id) }
        .not_to change(Friendship, :count)

      expect(flash[:alert]).to eq("Request not found.")
    end
  end

  describe "PATCH /dashboard/friends/:friend_id/visibility" do
    before { Flipper.enable_actor(FeatureFlags::FRIENDS_AVAILABILITY_ONLY, current_user) }

    it "does not change a friendship between two other users" do
      friendship = create(:friendship, :accepted, requester: grace, addressee: alan)

      patch dashboard_friend_visibility_path(grace.public_id), params: { visibility: "availability_only" }

      expect(flash[:alert]).to eq("Friend not found.")
      expect(friendship.reload).to be_requester_full
      expect(friendship).to be_addressee_full
    end
  end

  describe "PATCH /dashboard/friends/:friend_id/expiry" do
    before { Flipper.enable_actor(FeatureFlags::FRIEND_EXPIRY, current_user) }

    it "does not change a friendship between two other users" do
      friendship = create(:friendship, :accepted, :temporary, requester: grace, addressee: alan)

      patch dashboard_friend_expiry_path(grace.public_id), params: { permanent: "1" }

      expect(flash[:alert]).to eq("Friend not found.")
      expect(friendship.reload.expiry_proposal?).to be(false)
    end

    it "does not take the signed-in user's own id" do
      patch dashboard_friend_expiry_path(current_user.public_id), params: { permanent: "1" }

      expect(flash[:alert]).to eq("Friend not found.")
    end
  end

  describe "PATCH and DELETE /dashboard/friends/:friend_id/expiry_proposal" do
    let!(:friendship) do
      create(:friendship, :accepted, :temporary, requester: grace, addressee: alan).tap do |f|
        f.change_expiry!(to: nil, by: grace)
      end
    end

    it "does not accept a proposal between two other users" do
      patch dashboard_friend_expiry_proposal_path(grace.public_id)

      expect(flash[:alert]).to eq("Friend not found.")
      expect(friendship.reload.expires_at).to be_present
      expect(friendship.expiry_proposal?).to be(true)
    end

    it "does not decline a proposal between two other users" do
      delete dashboard_friend_expiry_proposal_path(grace.public_id)

      expect(flash[:alert]).to eq("Friend not found.")
      expect(friendship.reload.expiry_proposal?).to be(true)
    end

    it "refuses a friend with no open proposal" do
      own = create(:friendship, :accepted, :temporary, requester: current_user, addressee: alan)

      patch dashboard_friend_expiry_proposal_path(alan.public_id)

      expect(flash[:alert]).to eq("You are not authorized to perform this action.")
      expect(own.reload.expiry_proposal?).to be(false)
    end
  end

  # Only the dashboard's own forms sent these POST requests. No email or
  # bookmark can hold them, so they need no redirect.
  describe "old member action paths" do
    it "no longer routes them" do
      request = create(:friendship, requester: grace, addressee: current_user)

      %W[
        /dashboard/friends/#{request.id}/accept
        /dashboard/friends/#{request.id}/decline
        /dashboard/friends/#{grace.public_id}/accept_expiry
        /dashboard/friends/#{grace.public_id}/decline_expiry
      ].each do |path|
        post path
        expect(response).to have_http_status(:not_found), "expected #{path} to answer 404"
      end

      expect(request.reload).to be_pending
    end
  end
end
