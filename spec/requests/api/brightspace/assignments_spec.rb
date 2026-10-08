# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Brightspace assignments API", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers_for(user) }
  let(:connection) { create(:brightspace_connection, user: user) }
  let(:offering) { create(:brightspace_course_offering, connection: connection) }

  def json = response.parsed_body

  before { Flipper.enable_actor(FlipperFlags::BRIGHTSPACE, user) }

  describe "GET /api/assignments" do
    it "lists work across classes, ordered by effective deadline then id" do
      other_class = create(:brightspace_course_offering, connection: connection)
      due = 2.days.from_now.change(usec: 0)
      first  = create(:brightspace_assignment, course_offering: offering, due_at: due)
      second = create(:brightspace_assignment, course_offering: other_class, due_at: due)
      override = create(:brightspace_assignment, course_offering: offering, due_at: 5.days.from_now)
      create(:brightspace_assignment_preference, assignment: override, due_at_override: 1.day.from_now)

      get "/api/assignments", headers: headers

      expect(json["assignments"].pluck("id")).to eq([ override.public_id, first.public_id, second.public_id ])
    end

    it "filters by personal progress, counting no preference as not_started" do
      started = create(:brightspace_assignment, course_offering: offering)
      create(:brightspace_assignment_preference, assignment: started, progress: "in_progress")
      fresh = create(:brightspace_assignment, course_offering: offering)

      get "/api/assignments", params: { status: "not_started" }, headers: headers
      expect(json["assignments"].pluck("id")).to eq([ fresh.public_id ])

      get "/api/assignments", params: { status: "in_progress" }, headers: headers
      expect(json["assignments"].pluck("id")).to eq([ started.public_id ])
    end

    it "uses due_before as an exclusive cutoff on the effective deadline" do
      cutoff = 3.days.from_now.change(usec: 0)
      create(:brightspace_assignment, course_offering: offering, due_at: cutoff)
      before = create(:brightspace_assignment, course_offering: offering, due_at: cutoff - 1.second)
      moved = create(:brightspace_assignment, course_offering: offering, due_at: cutoff - 1.day)
      create(:brightspace_assignment_preference, assignment: moved, due_at_override: cutoff + 1.day)

      get "/api/assignments", params: { due_before: cutoff.utc.iso8601 }, headers: headers

      expect(json["assignments"].pluck("id")).to eq([ before.public_id ])
    end

    it "filters by term" do
      term = create(:term)
      kept = create(:brightspace_assignment, course_offering: create(:brightspace_course_offering, connection: connection, term: term))
      create(:brightspace_assignment, course_offering: offering)

      get "/api/assignments", params: { term_id: term.public_id }, headers: headers

      expect(json["assignments"].pluck("id")).to eq([ kept.public_id ])
    end

    it "leaves out removed work and the work of other users" do
      create(:brightspace_assignment, :removed, course_offering: offering)
      create(:brightspace_assignment)

      get "/api/assignments", headers: headers

      expect(json["assignments"]).to eq([])
    end

    it "answers 400 for a bad filter" do
      get "/api/assignments", params: { status: "late" }, headers: headers
      expect(response).to have_http_status(:bad_request)

      get "/api/assignments", params: { due_before: "tomorrow" }, headers: headers
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /api/assignments/:id" do
    it "returns every date apart, the effective deadline, and the preference" do
      assignment = create(:brightspace_assignment, course_offering: offering, description: "Read chapter 4",
                                                   due_at: Time.utc(2026, 10, 9, 3, 59), user_due_at: Time.utc(2026, 10, 11, 3, 59),
                                                   opens_at: Time.utc(2026, 10, 1), closes_at: nil)
      create(:brightspace_assignment_preference, assignment: assignment, progress: "done", due_at_override: Time.utc(2026, 10, 10, 22))

      get "/api/assignments/#{assignment.public_id}", headers: headers

      expect(json["assignment"]).to include(
        "id" => assignment.public_id, "class_id" => offering.public_id, "kind" => "assignment",
        "description" => "Read chapter 4",
        "due_at" => "2026-10-09T03:59:00Z", "user_due_at" => "2026-10-11T03:59:00Z",
        "opens_at" => "2026-10-01T00:00:00Z", "closes_at" => nil,
        "effective_due_at" => "2026-10-10T22:00:00Z",
        "preference" => { "progress" => "done", "due_at_override" => "2026-10-10T22:00:00Z" }
      )
    end

    it "answers 404 for another user's assignment" do
      get "/api/assignments/#{create(:brightspace_assignment).public_id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "/api/assignments/:id/preference" do
    let(:assignment) { create(:brightspace_assignment, course_offering: offering, submission_status: "not_submitted") }
    let(:path) { "/api/assignments/#{assignment.public_id}/preference" }

    it "returns the defaults without a saved preference" do
      get path, headers: headers

      expect(json).to eq("assignment_preference" => { "progress" => "not_started", "due_at_override" => nil },
                         "version" => offering.reload.version)
    end

    it "saves progress and an override and raises the class version" do
      version = offering.version

      put path, params: { assignment_preference: { progress: "done", due_at_override: "2026-10-08T22:00:00Z" } },
                headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["assignment_preference"]).to eq("progress" => "done", "due_at_override" => "2026-10-08T22:00:00Z")
      expect(json["version"]).not_to eq(version)
      expect(assignment.reload.submission_status).to eq("not_submitted")
    end

    it "changes only the fields in the body, and null clears the override" do
      create(:brightspace_assignment_preference, assignment: assignment, progress: "in_progress", due_at_override: 1.day.from_now)

      put path, params: { assignment_preference: { due_at_override: nil } }, headers: headers, as: :json

      expect(json["assignment_preference"]).to eq("progress" => "in_progress", "due_at_override" => nil)
    end

    it "answers 422 for a bad value" do
      put path, params: { assignment_preference: { progress: "late" } }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to match(/Progress/)

      put path, params: { assignment_preference: { due_at_override: "friday" } }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("due_at_override must be an ISO 8601 time")
    end

    it "answers 400 without the request root" do
      put path, params: { progress: "done" }, headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "answers 404 for another user's assignment" do
      put "/api/assignments/#{create(:brightspace_assignment).public_id}/preference",
          params: { assignment_preference: { progress: "done" } }, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
