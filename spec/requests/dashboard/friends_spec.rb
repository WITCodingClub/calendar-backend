# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Friends", type: :request do
  def create_user(email, first_name)
    User.create!(email: email, password: "password123", first_name: first_name,
                 last_name: "Student", confirmed_at: Time.current)
  end

  include ActiveJob::TestHelper

  let(:current_user) { create_user("me@wit.edu", "Ada") }
  let(:other_user)   { create_user("other@wit.edu", "Grace") }

  before { sign_in current_user }

  describe "POST /dashboard/friends" do
    it "creates a pending request to the given public id" do
      expect {
        post dashboard_friends_path, params: { friend_id: other_user.public_id }
      }.to change(Friendship, :count).by(1)

      expect(response).to redirect_to(dashboard_friends_path)
      expect(flash[:notice]).to eq("Friend request sent to Grace.")

      friendship = Friendship.last
      expect(friendship.requester).to eq(current_user)
      expect(friendship.addressee).to eq(other_user)
      expect(friendship).to be_pending
    end

    it "emails the requestee" do
      expect {
        post dashboard_friends_path, params: { friend_id: other_user.public_id }
      }.to have_enqueued_mail(FriendshipMailer, :request_received)
    end

    it "reports an unknown user" do
      expect {
        post dashboard_friends_path, params: { friend_id: "usr_doesnotexist" }
      }.not_to change(Friendship, :count)

      expect(flash[:alert]).to eq("User not found.")
    end

    it "refuses a request to yourself" do
      expect {
        post dashboard_friends_path, params: { friend_id: current_user.public_id }
      }.not_to change(Friendship, :count)

      expect(flash[:alert]).to eq("You can't add yourself.")
    end

    it "refuses a second request to the same user" do
      Friendship.create!(requester: current_user, addressee: other_user)

      expect {
        post dashboard_friends_path, params: { friend_id: other_user.public_id }
      }.not_to change(Friendship, :count)

      expect(flash[:alert]).to eq("You already have a request or friendship with Grace.")
    end

    it "refuses a request when the other user already sent one" do
      Friendship.create!(requester: other_user, addressee: current_user)

      expect {
        post dashboard_friends_path, params: { friend_id: other_user.public_id }
      }.not_to change(Friendship, :count)

      expect(flash[:alert]).to eq("You already have a request or friendship with Grace.")
    end
  end

  describe "POST /dashboard/friends/:id/accept" do
    it "accepts an incoming request" do
      friendship = Friendship.create!(requester: other_user, addressee: current_user)

      post accept_dashboard_friend_path(friendship.id)

      expect(response).to redirect_to(dashboard_friends_path)
      expect(flash[:notice]).to eq("Grace added as a friend.")
      expect(friendship.reload).to be_accepted
      expect(current_user.friends).to include(other_user)
    end

    it "does not accept a request addressed to somebody else" do
      third      = create_user("third@wit.edu", "Alan")
      friendship = Friendship.create!(requester: other_user, addressee: third)

      post accept_dashboard_friend_path(friendship.id)

      expect(flash[:alert]).to eq("Request not found.")
      expect(friendship.reload).to be_pending
    end
  end

  describe "POST /dashboard/friends/:id/decline" do
    it "deletes an incoming request" do
      friendship = Friendship.create!(requester: other_user, addressee: current_user)

      expect { post decline_dashboard_friend_path(friendship.id) }
        .to change(Friendship, :count).by(-1)

      expect(flash[:notice]).to eq("Request declined.")
    end
  end

  describe "DELETE /dashboard/friends/:id" do
    it "removes an accepted friend" do
      Friendship.create!(requester: other_user, addressee: current_user, status: :accepted)

      expect { delete dashboard_friend_path(other_user.public_id) }
        .to change(Friendship, :count).by(-1)

      expect(flash[:notice]).to eq("Grace removed.")
      expect(current_user.friends).to be_empty
    end

    it "reports a user who is not a friend" do
      expect { delete dashboard_friend_path(other_user.public_id) }
        .not_to change(Friendship, :count)

      expect(flash[:alert]).to eq("Friend not found.")
    end
  end
end
