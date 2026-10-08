# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Brightspace sync API", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers_for(user) }
  let(:body) { JSON.parse(file_fixture("brightspace/sync_snapshot.json").read) }

  def json = response.parsed_body

  before { Flipper.enable_actor(FlipperFlags::BRIGHTSPACE, user) }

  describe "POST /api/brightspace/sync" do
    let!(:connection) { create(:brightspace_connection, user: user, host: "brightspace.example.edu", learner_id: "98765") }

    it "imports the snapshot" do
      post "/api/brightspace/sync", params: body, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["sync_id"]).to start_with("bss_")
      expect(json["status"]).to eq("complete")
      expect(json["changed_classes"].first["id"]).to start_with("bcl_")
      expect(connection.course_offerings.count).to eq(1)
    end

    it "answers the same snapshot again with the same body" do
      post "/api/brightspace/sync", params: body, headers: headers, as: :json
      first = json

      post "/api/brightspace/sync", params: body, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json).to eq(first)
    end

    it "answers 409 for a reused snapshot id with other data" do
      post "/api/brightspace/sync", params: body, headers: headers, as: :json
      body["classes"][0]["title"] = "Changed"

      post "/api/brightspace/sync", params: body, headers: headers, as: :json

      expect(response).to have_http_status(:conflict)
      expect(json).to include("code" => "SNAPSHOT_CONFLICT", "error" => be_present)
    end

    it "answers 409 for another account" do
      body["learner_id"] = "1"

      post "/api/brightspace/sync", params: body, headers: headers, as: :json

      expect(response).to have_http_status(:conflict)
      expect(json["code"]).to eq("CONNECTION_MISMATCH")
    end

    it "answers 400 for a missing field" do
      post "/api/brightspace/sync", params: body.except("snapshot_id"), headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(json).to include("success" => false, "code" => "VALIDATION_FAILED")
    end

    it "answers 422 for a bad value" do
      body["classes"][0]["assignments"][0]["due_at"] = "soon"

      post "/api/brightspace/sync", params: body, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("classes[0].assignments[0].due_at must be an ISO 8601 time")
    end

    it "ignores a user_id in the payload" do
      other = create(:user)
      body["user_id"] = other.public_id

      post "/api/brightspace/sync", params: body, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(Brightspace::CourseOffering.for_user(other)).to be_empty
    end

    it "answers 404 while the flag is off" do
      Flipper.disable_actor(FlipperFlags::BRIGHTSPACE, user)

      post "/api/brightspace/sync", params: body, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/brightspace/status" do
    it "returns null and no classes without a connection" do
      get "/api/brightspace/status", headers: headers

      expect(json).to eq("connection" => nil, "classes" => [])
    end

    it "returns each section's last collection and error" do
      create(:brightspace_connection, user: user, host: "brightspace.example.edu", learner_id: "98765")
      body["classes"][0]["section_errors"] = { "grades" => "Gradebook timed out" }
      body["classes"][0]["complete_sections"] = %w[assignments announcements]
      body["reconnect_required"] = true
      post "/api/brightspace/sync", params: body, headers: headers, as: :json

      get "/api/brightspace/status", headers: headers

      expect(json["connection"]).to include("reconnect_required" => true)
      sections = json["classes"].first["sections"]
      expect(sections["assignments"]).to include("last_collected_at" => "2026-10-06T17:00:00Z", "complete" => true, "error" => nil)
      expect(sections["grades"]).to include("last_collected_at" => nil, "error" => "Gradebook timed out")
    end

    it "shows the data of a disconnected account" do
      connection = create(:brightspace_connection, :disconnected, user: user)
      create(:brightspace_course_offering, connection: connection)

      get "/api/brightspace/status", headers: headers

      expect(json["connection"]).to include("status" => "disconnected")
      expect(json["classes"].size).to eq(1)
    end
  end
end
