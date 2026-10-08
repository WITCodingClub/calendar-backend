# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Brightspace grades, syllabus, and scenario API", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers_for(user) }
  let!(:connection) { create(:brightspace_connection, user: user, host: "brightspace.example.edu", learner_id: "98765") }
  let(:snapshot) { JSON.parse(file_fixture("brightspace/sync_snapshot.json").read) }
  let(:offering) { connection.course_offerings.sole }

  def json = response.parsed_body

  before do
    Flipper.enable_actor(FlipperFlags::BRIGHTSPACE, user)
    Brightspace::SyncIngestor.new(user: user, params: snapshot).call
  end

  describe "GET /api/classes/:id/grades" do
    it "returns the gradebook with zero and ungraded apart" do
      get "/api/classes/#{offering.public_id}/grades", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json["reported_total"]).to eq("points_earned" => 41.5, "points_possible" => 50.0, "percent" => 83.0, "letter" => "B")
      labs = json["categories"].find { |category| category["name"] == "Labs" }
      expect(labs).to include("weight" => 40.0, "drop_lowest" => 1, "drop_highest" => nil, "extra_credit" => false)

      items = json["items"].index_by { |item| item["source_id"] }
      expect(items["7003"]).to include("points_earned" => 0.0, "grading_status" => "graded")
      expect(items["7002"]).to include("points_earned" => nil, "grading_status" => "ungraded", "category_id" => labs["id"],
                                       "assignment_id" => offering.assignments.find_by!(source_id: "56789").public_id)
      expect(json).to include("preferences" => { "mode" => "brightspace", "categories" => [] }, "scenarios" => [],
                              "version" => offering.version)
    end
  end

  describe "GET /api/classes/:id/syllabus" do
    it "returns the source and the extracted rules, with nothing confirmed yet" do
      get "/api/classes/#{offering.public_id}/syllabus", headers: headers

      expect(json["source"]).to include("source_id" => "content-55", "title" => "Course Syllabus", "revision" => "2026-09-01T00:00:00Z")
      expect(json["extracted"]).to eq(snapshot["classes"][0]["syllabus"]["extracted"])
      expect(json["confirmed"]).to be_nil
    end
  end

  describe "PUT /api/classes/:id/syllabus/preference" do
    let(:path) { "/api/classes/#{offering.public_id}/syllabus/preference" }
    let(:confirmed) { { "categories" => [ { "name" => "Labs", "weight" => 45, "source_ref" => "page 2" } ] } }

    it "saves the confirmed rules for the current revision" do
      put path, params: { syllabus_preference: { source_revision: "2026-09-01T00:00:00Z", confirmed: confirmed } },
                headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["syllabus_preference"]).to include("source_revision" => "2026-09-01T00:00:00Z", "confirmed" => confirmed)
      expect(json["version"]).to eq(offering.reload.version)
    end

    it "answers 409 for an old revision" do
      put path, params: { syllabus_preference: { source_revision: "2026-01-01", confirmed: confirmed } }, headers: headers, as: :json

      expect(response).to have_http_status(:conflict)
      expect(json["code"]).to eq("SYLLABUS_REVISION_MISMATCH")
    end

    it "keeps the confirmed rules through a later import" do
      put path, params: { syllabus_preference: { source_revision: "2026-09-01T00:00:00Z", confirmed: confirmed } },
                headers: headers, as: :json
      snapshot["snapshot_id"] = SecureRandom.uuid
      snapshot["collected_at"] = "2026-10-07T17:00:00Z"
      snapshot["classes"][0]["syllabus"]["revision"] = "2026-10-01T00:00:00Z"
      Brightspace::SyncIngestor.new(user: user, params: snapshot).call

      get "/api/classes/#{offering.public_id}/syllabus", headers: headers

      expect(json["source"]["revision"]).to eq("2026-10-01T00:00:00Z")
      expect(json["confirmed"]).to include("source_revision" => "2026-09-01T00:00:00Z", "confirmed" => confirmed)
    end

    it "does not change grade settings" do
      put path, params: { syllabus_preference: { source_revision: "2026-09-01T00:00:00Z", confirmed: confirmed } },
                headers: headers, as: :json

      expect(offering.reload.preference).to be_nil
    end
  end

  describe "grade scenarios" do
    let(:path) { "/api/classes/#{offering.public_id}/grade_scenarios" }
    let(:item) { offering.grade_items.find_by!(source_id: "7002") }

    it "creates, lists, updates, and deletes a scenario without touching imported grades" do
      post path, params: { grade_scenario: { name: "Ace lab 4", scores: [ { item_id: item.public_id, points: 10 } ] } },
                 headers: headers, as: :json

      expect(response).to have_http_status(:created)
      scenario = json["scenario"]
      expect(scenario).to include("name" => "Ace lab 4", "scores" => [ { "item_id" => item.public_id, "points" => 10 } ])
      expect(json["version"]).to eq(offering.reload.version)
      expect(item.reload.points_earned).to be_nil

      get path, headers: headers
      expect(json["scenarios"].pluck("id")).to eq([ scenario["id"] ])

      put "#{path}/#{scenario['id']}", params: { grade_scenario: { name: "Pass lab 4" } }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(json["scenario"]).to include("name" => "Pass lab 4", "scores" => scenario["scores"])

      delete "#{path}/#{scenario['id']}", headers: headers
      expect(response).to have_http_status(:no_content)
      expect(offering.grade_scenarios).to be_empty
    end

    it "answers 422 for a score of an unknown item" do
      post path, params: { grade_scenario: { name: "X", scores: [ { item_id: "bgi_nope", points: 1 } ] } }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to match(/not a grade item of this class/)
    end

    it "answers 404 for a scenario of another class" do
      other = create(:brightspace_grade_scenario)

      delete "#{path}/#{other.public_id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  it "answers 404 for the grades of another user's class" do
    get "/api/classes/#{create(:brightspace_course_offering).public_id}/grades", headers: headers

    expect(response).to have_http_status(:not_found)
  end
end
