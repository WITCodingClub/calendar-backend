# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Brightspace classes API", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:headers) { auth_headers_for(user) }
  let(:connection) { create(:brightspace_connection, user: user) }

  def json = response.parsed_body

  before { Flipper.enable_actor(FlipperFlags::BRIGHTSPACE, user) }

  describe "GET /api/classes" do
    it "lists the classes of the current connection with the next deadline" do
      offering = create(:brightspace_course_offering, :with_course, connection: connection, title: "Data Structures")
      create(:brightspace_assignment, course_offering: offering, title: "Later", due_at: 5.days.from_now)
      soon = create(:brightspace_assignment, course_offering: offering, title: "Soon", due_at: 1.day.from_now)
      create(:brightspace_assignment, course_offering: offering, title: "Past", due_at: 1.day.ago)

      get "/api/classes", headers: headers

      expect(response).to have_http_status(:ok)
      item = json["classes"].sole
      expect(item).to include("id" => offering.public_id, "course_id" => offering.course.public_id,
                              "title" => "Data Structures", "version" => offering.version)
      expect(item["term"]).to include("pub_id" => offering.term.public_id)
      expect(item["next_deadline"]).to include("assignment_id" => soon.public_id, "title" => "Soon")
      expect(json["meta"]).to eq("current_page" => 1, "total_pages" => 1, "total_count" => 1, "per_page" => 25)
    end

    it "skips work that the user marked done for the next deadline" do
      offering = create(:brightspace_course_offering, connection: connection)
      done = create(:brightspace_assignment, course_offering: offering, due_at: 1.day.from_now)
      create(:brightspace_assignment_preference, assignment: done, progress: "done")
      next_one = create(:brightspace_assignment, course_offering: offering, due_at: 2.days.from_now)

      get "/api/classes", headers: headers

      expect(json["classes"].sole["next_deadline"]["assignment_id"]).to eq(next_one.public_id)
    end

    it "filters by the backend term public id" do
      term = create(:term)
      kept = create(:brightspace_course_offering, connection: connection, term: term)
      create(:brightspace_course_offering, connection: connection)

      get "/api/classes", params: { term_id: term.public_id }, headers: headers

      expect(json["classes"].pluck("id")).to eq([ kept.public_id ])
    end

    it "pages the list" do
      create_list(:brightspace_course_offering, 3, connection: connection)

      get "/api/classes", params: { page: 2, per_page: 2 }, headers: headers

      expect(json["classes"].size).to eq(1)
      expect(json["meta"]).to include("current_page" => 2, "total_pages" => 2, "total_count" => 3, "per_page" => 2)
    end

    it "never shows the classes of another user" do
      create(:brightspace_course_offering)

      get "/api/classes", headers: headers

      expect(json["classes"]).to eq([])
    end

    it "answers 404 while the flag is off" do
      Flipper.disable_actor(FlipperFlags::BRIGHTSPACE, user)

      get "/api/classes", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/classes/:id" do
    let(:offering) { create(:brightspace_course_offering, connection: connection) }

    it "returns the class with upcoming work, announcements, preferences, and sync state" do
      upcoming = create(:brightspace_assignment, course_offering: offering, due_at: 1.day.from_now)
      create(:brightspace_assignment, :removed, course_offering: offering, due_at: 1.day.from_now)
      announcement = create(:brightspace_announcement, course_offering: offering)

      get "/api/classes/#{offering.public_id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json["class"]["id"]).to eq(offering.public_id)
      expect(json["upcoming_assignments"].pluck("id")).to eq([ upcoming.public_id ])
      expect(json["announcements"].pluck("id")).to eq([ announcement.public_id ])
      expect(json["preferences"]["calendar"]).to include("sync_enabled" => true, "reminder_settings" => nil)
      expect(json["preferences"]["grades"]).to eq("mode" => "brightspace", "categories" => [])
      expect(json["sync"].keys).to match_array(Brightspace::SECTIONS)
    end

    it "answers 404 for a class of another user" do
      other = create(:brightspace_course_offering)

      get "/api/classes/#{other.public_id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "answers 404 for a raw database id" do
      get "/api/classes/#{offering.id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/classes/:id/assignments" do
    it "lists the class's assignments by effective deadline with undated work last" do
      offering = create(:brightspace_course_offering, connection: connection)
      undated  = create(:brightspace_assignment, course_offering: offering, due_at: nil)
      later    = create(:brightspace_assignment, course_offering: offering, due_at: 3.days.from_now)
      special  = create(:brightspace_assignment, course_offering: offering, due_at: 5.days.from_now, user_due_at: 1.day.from_now)
      create(:brightspace_assignment, course_offering: create(:brightspace_course_offering, connection: connection))

      get "/api/classes/#{offering.public_id}/assignments", headers: headers

      expect(json["assignments"].pluck("id")).to eq([ special.public_id, later.public_id, undated.public_id ])
      expect(json["meta"]["total_count"]).to eq(3)
    end
  end
end
