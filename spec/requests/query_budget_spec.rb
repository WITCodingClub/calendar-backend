# frozen_string_literal: true

require "rails_helper"

# Hot paths must not send more queries when a user has more friends, classes,
# or meeting times (#653, #654). Each example runs a request with a small data
# set and again with a large one, and expects the same number of queries.
# Prosopite also scans each request (config/initializers/prosopite.rb).
RSpec.describe "Query budget for hot paths", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }
  let(:term)    { create(:term) }

  def add_friends(owner, count)
    create_list(:user, count).each do |friend|
      create(:friendship, :accepted, requester: owner, addressee: friend)
    end
  end

  def add_pending_requests(owner, count)
    count.times do
      create(:friendship, requester: create(:user), addressee: owner)
      create(:friendship, requester: owner, addressee: create(:user))
    end
  end

  # A class with a faculty member and two meeting times in two rooms.
  def enroll(owner, count)
    building = create(:building)
    count.times do
      course = create(:course, term: term)
      create(:course_faculty, course: course, faculty: create(:faculty))
      %i[monday wednesday].each do |day|
        meeting_time = create(:course_meeting_time, course: course, day_of_week: day)
        create(:course_meeting_time_room, meeting_time: meeting_time, room: create(:room, building: building))
      end
      create(:enrollment, user: owner, course: course, term: term)
    end
  end

  describe "GET /api/friends" do
    it "lists 55 friends with the same number of queries as 2 friends" do
      add_friends(user, 2)
      add_pending_requests(user, 3)
      get "/api/friends", headers: headers
      small = count_queries { get "/api/friends", headers: headers }

      add_friends(user, 53)
      large = count_queries { get "/api/friends", headers: headers }

      expect(response.parsed_body["friends"].size).to eq(55)
      expect(large).to eq(small)
    end
  end

  describe "GET /api/friends/requests" do
    it "lists 20 pending requests with the same number of queries as 2" do
      add_friends(user, 5)
      add_pending_requests(user, 1)
      get "/api/friends/requests", headers: headers
      small = count_queries { get "/api/friends/requests", headers: headers }

      add_pending_requests(user, 9)
      large = count_queries { get "/api/friends/requests", headers: headers }

      expect(response.parsed_body["incoming"].size).to eq(10)
      expect(large).to eq(small)
    end
  end

  describe "GET /api/friends/:friend_id/processed_events" do
    it "builds a friend's schedule with the same number of queries for 1 class and 6 classes" do
      friend = create(:user)
      create(:friendship, :accepted, requester: user, addressee: friend)
      add_friends(user, 50)
      path = "/api/friends/#{friend.public_id}/processed_events"
      params = { term_uid: term.uid }

      enroll(friend, 1)
      get path, params: params, headers: headers
      small = count_queries { get path, params: params, headers: headers }

      enroll(friend, 5)
      large = count_queries { get path, params: params, headers: headers }

      expect(response.parsed_body["classes"].size).to eq(6)
      expect(large).to eq(small)
    end
  end

  describe "GET /api/user/processed_events" do
    it "builds the user's schedule with the same number of queries for 1 class and 6 classes" do
      params = { term_uid: term.uid }

      enroll(user, 1)
      get "/api/user/processed_events", params: params, headers: headers
      small = count_queries { get "/api/user/processed_events", params: params, headers: headers }

      enroll(user, 5)
      large = count_queries { get "/api/user/processed_events", params: params, headers: headers }

      expect(response).to have_http_status(:ok)
      expect(large).to eq(small)
    end
  end

  describe "GET /calendar/:calendar_token" do
    it "renders the ICS feed with the same number of queries for 1 class and 6 classes" do
      path = "/calendar/#{user.calendar_token}"

      enroll(user, 1)
      get path
      small = count_queries { get path }

      enroll(user, 5)
      large = count_queries { get path }

      expect(response.body.scan("BEGIN:VEVENT").size).to eq(12)
      expect(large).to eq(small)
    end
  end

  describe "GET /api/user/feature_flags" do
    it "answers in a fixed number of queries" do
      get "/api/user/feature_flags", headers: headers
      queries = count_queries { get "/api/user/feature_flags", headers: headers }

      expect(response).to have_http_status(:ok)
      expect(queries).to be <= 6
    end
  end

  describe "dashboard friends pages" do
    # The onboarding gate (#644) sends a user with no courses away from these pages.
    let(:user) { create(:user, :with_processed_courses) }

    before { sign_in user }

    it "renders the friends list for 55 friends with the same number of queries as 2" do
      add_friends(user, 2)
      add_pending_requests(user, 3)
      get "/dashboard/friends"
      small = count_queries { get "/dashboard/friends" }

      add_friends(user, 53)
      large = count_queries { get "/dashboard/friends" }

      expect(response).to have_http_status(:ok)
      expect(large).to eq(small)
    end

    it "renders a friend's schedule with the same number of queries for 1 class and 6 classes" do
      friend = create(:user)
      create(:friendship, :accepted, requester: user, addressee: friend)
      path = "/dashboard/friends/#{friend.public_id}?term_uid=#{term.uid}"

      enroll(friend, 1)
      get path
      small = count_queries { get path }

      enroll(friend, 5)
      large = count_queries { get path }

      expect(response).to have_http_status(:ok)
      expect(large).to eq(small)
    end
  end
end
