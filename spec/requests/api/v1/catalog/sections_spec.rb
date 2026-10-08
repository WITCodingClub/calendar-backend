# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Catalog::Sections", type: :request do
  include_context "catalog fixtures"

  def json = JSON.parse(response.body)
  def crns = json["data"].map { |s| s["crn"] }

  describe "GET /api/v1/catalog/sections" do
    it "returns active sections with pagination metadata" do
      get "/api/v1/catalog/sections"

      expect(response).to have_http_status(:ok)
      expect(crns).to eq([ 10_001, 10_002, 10_003, 20_001 ])
      expect(json["meta"]).to include(
        "page" => 1, "per_page" => 50, "total_count" => 4, "total_pages" => 1
      )
    end

    it "serializes the full section payload" do
      get "/api/v1/catalog/sections", params: { crn: 10_001 }

      section = json["data"].first
      expect(section).to include(
        "crn"                => 10_001,
        "subject"            => "Computer Science (COMP)",
        "subject_code"       => "COMP",
        "course_number"      => 1000,
        "section_number"     => "01",
        "course_code"        => "COMP 1000-01",
        "title"              => "Course 1000",
        "schedule_type"      => "lecture",
        "schedule_type_code" => "LEC",
        "credit_hours"       => 4,
        "status"             => "active"
      )
      expect(section["term"]).to eq("uid" => 202_710, "name" => "Fall 2026")
      expect(section["seats"]).to eq("capacity" => nil, "available" => nil)
      expect(section["pub_id"]).to be_present
    end

    it "reports a section that stands alone as unlinked" do
      get "/api/v1/catalog/sections", params: { crn: 10_001 }

      expect(json["data"].first["linked"]).to eq(
        "required" => false, "identifier" => nil, "crns" => [], "pub_ids" => []
      )
    end

    it "names the sections Banner pairs with this one" do
      comp2000.update!(link_identifier: "A1", is_section_linked: true)
      comp2000b.update!(link_identifier: "B1", is_section_linked: true)

      get "/api/v1/catalog/sections", params: { crn: 10_002 }

      expect(json["data"].first["linked"]).to eq(
        "required" => true, "identifier" => "A1", "crns" => [ 10_003 ],
        "pub_ids" => [ comp2000b.public_id ]
      )
    end

    it "finds a section by the public id it publishes" do
      get "/api/v1/catalog/sections", params: { pub_id: comp2000.public_id }

      expect(json["data"].map { |s| s["crn"] }).to eq([ 10_002 ])
    end

    it "serializes meeting times in day then time order" do
      get "/api/v1/catalog/sections", params: { crn: 10_001 }

      meetings = json["data"].first["meeting_times"]
      expect(meetings.map { |m| m["day"] }).to eq(%w[monday friday])
      expect(meetings.first).to include(
        "begin_time"       => "09:00",
        "end_time"         => "10:15",
        "duration_minutes" => 75,
        "meeting_type"     => "lecture"
      )
      expect(meetings.first["location"]).to include(
        "building" => { "abbreviation" => "ANNX", "name" => "Test Annex" }
      )
    end

    it "returns null location when no room is assigned" do
      get "/api/v1/catalog/sections", params: { crn: 10_002 }

      expect(json["data"].first["meeting_times"].first["location"]).to be_nil
    end

    it "includes the final exam when one is scheduled" do
      get "/api/v1/catalog/sections", params: { crn: 10_001 }

      expect(json["data"].first["final_exam"]).to include(
        "date" => "2026-12-17", "location" => "ANNX 306"
      )
    end

    it "omits instructor contact details" do
      get "/api/v1/catalog/sections", params: { crn: 10_001 }

      instructor = json["data"].first["instructors"].first
      expect(instructor["name"]).to eq("Ada Byron")
      expect(instructor.keys).not_to include("email", "phone", "office_location")
    end

    it "reports Rate My Professors scores only when ratings exist" do
      get "/api/v1/catalog/sections", params: { crn: 10_001 }
      expect(json["data"].first["instructors"].first["rmp"]).to include(
        "avg_rating" => 4.5, "num_ratings" => 12, "would_take_again_percent" => 88.0
      )

      get "/api/v1/catalog/sections", params: { crn: 10_002 }
      expect(json["data"].first["instructors"].first["rmp"]).to be_nil
    end

    it "collapses duplicate meeting rows from concurrent ingests" do
      add_meeting(comp2000, :tuesday, 1300, 1415)
      get "/api/v1/catalog/sections", params: { crn: 10_002 }

      expect(json["data"].first["meeting_times"].size).to eq(1)
    end
  end

  describe "filters" do
    it "accepts comma-separated lists" do
      get "/api/v1/catalog/sections", params: { crn: "10001,20001" }
      expect(crns).to eq([ 10_001, 20_001 ])
    end

    it "filters by subject code, term, and day" do
      get "/api/v1/catalog/sections",
          params: { subject: "COMP", term_uid: 202_710, meets_on: "friday" }

      expect(crns).to eq([ 10_001, 10_003 ])
    end

    it "filters by free days and time window" do
      get "/api/v1/catalog/sections", params: { free_days: "friday", begins_after: "10:00" }

      expect(crns).to eq([ 10_002, 20_001 ])
    end

    it "echoes the applied filters back in the metadata" do
      get "/api/v1/catalog/sections", params: { subject: "COMP" }

      expect(json["meta"]["filters"]).to eq("subject" => [ "COMP" ])
    end

    it "returns a structured 400 for an unknown day" do
      get "/api/v1/catalog/sections", params: { meets_on: "funday" }

      expect(response).to have_http_status(:bad_request)
      expect(json["code"]).to eq("INVALID_FILTER")
      expect(json["error"]).to match(/Unknown day/)
    end

    it "returns a structured 400 for a malformed time" do
      get "/api/v1/catalog/sections", params: { begins_after: "half past nine" }

      expect(response).to have_http_status(:bad_request)
      expect(json["code"]).to eq("INVALID_FILTER")
    end

    it "ignores unknown query parameters rather than erroring" do
      get "/api/v1/catalog/sections", params: { sort_by: "title" }

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /api/v1/catalog/sections/:crn/similar" do
    before do
      give_embedding(comp1000, 0.00)
      give_embedding(comp2000, 0.10)
      give_embedding(comp2000b, 0.11)
      give_embedding(math1750, 0.90)
    end

    it "returns the closest sections of the same term, nearest first" do
      get "/api/v1/catalog/sections/10001/similar"

      expect(response).to have_http_status(:ok)
      expect(crns).to eq([ 10_002, 10_003 ])
      expect(json["meta"]).to eq("crn" => 10_001, "limit" => 10)
    end

    it "honours the limit" do
      get "/api/v1/catalog/sections/10001/similar", params: { limit: 1 }

      expect(crns).to eq([ 10_002 ])
      expect(json["meta"]["limit"]).to eq(1)
    end

    it "caps the limit" do
      get "/api/v1/catalog/sections/10001/similar", params: { limit: 5000 }

      expect(json["meta"]["limit"]).to eq(50)
    end

    it "returns an empty list for a section with no vector" do
      comp1000.update_columns(embedding: nil, embedding_digest: nil) # rubocop:disable Rails/SkipsModelValidations

      get "/api/v1/catalog/sections/10001/similar"

      expect(response).to have_http_status(:ok)
      expect(json["data"]).to be_empty
    end

    it "returns 404 for a CRN that does not exist" do
      get "/api/v1/catalog/sections/99999/similar"

      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end
  end

  describe "semantic search", :semantic_search do
    before do
      give_embedding(comp1000, 0.05)
      give_embedding(math1750, 0.95)
      stub_openai_embeddings([ embedding_vector(0.0) ])
    end

    it "ranks the sections that mean what the query means" do
      get "/api/v1/catalog/sections", params: { q: "learn to program", semantic: "true" }

      expect(response).to have_http_status(:ok)
      expect(crns).to eq([ 10_001, 20_001 ])
      expect(json["meta"]["total_count"]).to eq(2)
    end

    it "reports the filters it used" do
      get "/api/v1/catalog/sections", params: { q: "learn to program", semantic: "true" }

      expect(json["meta"]["filters"]).to include("q" => "learn to program", "semantic" => "true")
    end

    it "searches the literal words when semantic is not asked for" do
      get "/api/v1/catalog/sections", params: { q: "Course 1000" }

      expect(crns).to eq([ 10_001 ])
      expect(a_request(:post, EmbeddingService::API_URL)).not_to have_been_made
    end
  end

  describe "pagination" do
    it "honours page and per_page" do
      get "/api/v1/catalog/sections", params: { page: 2, per_page: 2 }

      expect(crns).to eq([ 10_003, 20_001 ])
      expect(json["meta"]).to include("page" => 2, "per_page" => 2, "total_pages" => 2)
    end

    it "caps per_page so one request cannot pull the whole catalog" do
      get "/api/v1/catalog/sections", params: { per_page: 5000 }

      expect(json["meta"]["per_page"]).to eq(Catalog::SectionQuery::MAX_PER_PAGE)
    end

    it "treats a zero or negative page as the first page" do
      get "/api/v1/catalog/sections", params: { page: 0 }

      expect(json["meta"]["page"]).to eq(1)
    end
  end

  describe "GET /api/v1/catalog/sections/:crn" do
    it "returns the section" do
      get "/api/v1/catalog/sections/10001"

      expect(response).to have_http_status(:ok)
      expect(json["data"]["crn"]).to eq(10_001)
    end

    it "returns cancelled sections so a saved CRN never silently disappears" do
      get "/api/v1/catalog/sections/10999"

      expect(response).to have_http_status(:ok)
      expect(json["data"]["status"]).to eq("cancelled")
    end

    it "returns a structured 404 for an unknown CRN" do
      get "/api/v1/catalog/sections/44444"

      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end
  end
end
