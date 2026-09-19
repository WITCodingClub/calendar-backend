# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Friends", type: :request do
  def create_user(first_name)
    create(:user, first_name: first_name)
  end

  include ActiveJob::TestHelper

  let(:current_user) { create_user("Ada") }
  let(:other_user)   { create_user("Grace") }

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
      create(:friendship, requester: current_user, addressee: other_user)

      expect {
        post dashboard_friends_path, params: { friend_id: other_user.public_id }
      }.not_to change(Friendship, :count)

      expect(flash[:alert]).to eq("You already have a request or friendship with Grace.")
    end

    it "refuses a request when the other user already sent one" do
      create(:friendship, requester: other_user, addressee: current_user)

      expect {
        post dashboard_friends_path, params: { friend_id: other_user.public_id }
      }.not_to change(Friendship, :count)

      expect(flash[:alert]).to eq("You already have a request or friendship with Grace.")
    end
  end

  describe "GET /dashboard/friends" do
    it "links each friend to their schedule" do
      create(:friendship, :accepted, requester: current_user, addressee: other_user)

      get dashboard_friends_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(dashboard_friend_path(other_user.public_id))
    end
  end

  describe "GET /dashboard/friends/requests" do
    # The show route would also match this path, so this guards the route order.
    it "still renders the requests page" do
      get requests_dashboard_friends_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /dashboard/friends/:id" do
    let(:term)   { create(:term) }
    let(:course) { create(:course, term: term, subject: "MATH", course_number: 2300, title: "Linear Algebra") }

    before do
      create(:course_meeting_time, course: course)
      create(:enrollment, user: other_user, course: course)
    end

    it "shows an accepted friend's courses" do
      create(:friendship, :accepted, requester: other_user, addressee: current_user)

      get dashboard_friend_path(other_user.public_id), params: { term_uid: term.uid, view: "list" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ERB::Util.html_escape("#{other_user.full_name}'s Schedule"))
      expect(response.body).to include("MATH 2300")
      expect(response.body).to include("Linear Algebra")
    end

    it "keeps the week navigation on the friend's page" do
      create(:friendship, :accepted, requester: current_user, addressee: other_user)

      get dashboard_friend_path(other_user.public_id),
          params: { term_uid: term.uid, view: "week", week_start: "2026-09-14" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(
        ERB::Util.html_escape(dashboard_friend_path(other_user.public_id, view: "week", term_uid: term.uid, week_start: "2026-09-21"))
      )
      expect(response.body).to include("MATH 2300")
    end

    it "does not show the signed-in user's own courses" do
      create(:friendship, :accepted, requester: current_user, addressee: other_user)
      own_course = create(:course, term: term, subject: "HIST", course_number: 1100)
      create(:enrollment, user: current_user, course: own_course)

      get dashboard_friend_path(other_user.public_id), params: { term_uid: term.uid, view: "list" }

      expect(response.body).to include("MATH 2300")
      expect(response.body).not_to include("HIST 1100")
    end

    it "refuses a user with only a pending request" do
      create(:friendship, requester: current_user, addressee: other_user)

      get dashboard_friend_path(other_user.public_id), params: { term_uid: term.uid }

      expect(response).to redirect_to(dashboard_friends_path)
      expect(flash[:alert]).to eq("Friend not found.")
    end

    it "refuses a user who is not a friend" do
      get dashboard_friend_path(other_user.public_id), params: { term_uid: term.uid }

      expect(response).to redirect_to(dashboard_friends_path)
      expect(flash[:alert]).to eq("Friend not found.")
    end
  end

  describe "POST /dashboard/friends/:id/accept" do
    it "accepts an incoming request" do
      friendship = create(:friendship, requester: other_user, addressee: current_user)

      post accept_dashboard_friend_path(friendship.id)

      expect(response).to redirect_to(dashboard_friends_path)
      expect(flash[:notice]).to eq("Grace added as a friend.")
      expect(friendship.reload).to be_accepted
      expect(current_user.friends).to include(other_user)
    end

    it "does not accept a request addressed to somebody else" do
      third      = create_user("Alan")
      friendship = create(:friendship, requester: other_user, addressee: third)

      post accept_dashboard_friend_path(friendship.id)

      expect(flash[:alert]).to eq("Request not found.")
      expect(friendship.reload).to be_pending
    end
  end

  describe "POST /dashboard/friends/:id/decline" do
    it "deletes an incoming request" do
      friendship = create(:friendship, requester: other_user, addressee: current_user)

      expect { post decline_dashboard_friend_path(friendship.id) }
        .to change(Friendship, :count).by(-1)

      expect(flash[:notice]).to eq("Request declined.")
    end
  end

  describe "DELETE /dashboard/friends/:id" do
    it "removes an accepted friend" do
      create(:friendship, :accepted, requester: other_user, addressee: current_user)

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
