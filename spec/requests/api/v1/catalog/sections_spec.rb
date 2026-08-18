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
