# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Catalog courses API", type: :request do
  def json = response.parsed_body

  let(:term) { create(:term, uid: 202720, year: 2027, season: :spring) }
  let!(:comp1050) { create(:catalog_course, subject_code: "COMP", course_number: 1050, title: "Computer Science II") }
  let!(:comp2000) do
    create(:catalog_course, :with_details, subject_code: "COMP", course_number: 2000, title: "Data Structures",
                                           source_term: term,
                                           prerequisites: {
                                             "type" => "or",
                                             "operands" => [
                                               { "type" => "course", "subject_code" => "COMP", "course_number" => 1050, "min_grade" => "D" },
                                               { "type" => "course", "subject_code" => "COMP", "course_number" => 128 },
                                               { "type" => "test", "name" => "WIT Math Assessment", "score" => "1500" }
                                             ]
                                           },
                                           corequisites: [ { "subject_code" => "COMP", "course_number" => 1050 } ],
                                           restrictions: [ { "heading" => "Cannot be enrolled in", "values" => [ "WFD" ] } ])
  end

  before do
    create(:course_prerequisite, catalog_course: comp2000, required_catalog_course: comp1050)
  end

  describe "GET /api/v1/catalog/courses/:code" do
    it "returns the course with linked prerequisites and what it unlocks" do
      get "/api/v1/catalog/courses/COMP2000"

      expect(response).to have_http_status(:ok)
      data = json["data"]
      expect(data).to include("code" => "COMP 2000", "title" => "Data Structures", "typically_offered" => %w[fall spring],
                              "details_term_uid" => 202720)
      operands = data["prerequisites"]["operands"]
      expect(operands.first).to include("code" => "COMP 1050", "title" => "Computer Science II", "linked" => true, "min_grade" => "D")
      expect(operands.second).to include("code" => "COMP 128", "title" => nil, "linked" => false)
      expect(operands.third).to eq("type" => "test", "name" => "WIT Math Assessment", "score" => "1500")
      expect(data["corequisites"].first).to include("code" => "COMP 1050", "linked" => true)
      expect(data["restrictions"]).to eq([ { "heading" => "Cannot be enrolled in", "values" => [ "WFD" ] } ])
      expect(data).not_to have_key("sections")
    end

    it "accepts a code with a space and lists what a course unlocks" do
      get "/api/v1/catalog/courses/#{ERB::Util.url_encode('comp 1050')}"

      expect(json["data"]["unlocks"]).to eq([ { "code" => "COMP 2000", "subject_code" => "COMP", "course_number" => 2000,
                                                "title" => "Data Structures", "credit_hours" => 4, "typically_offered" => %w[fall spring] } ])
    end

    it "adds the sections of a term" do
      section = create(:course, term: term, subject: "Computer Science (COMP)", course_number: 2000)

      get "/api/v1/catalog/courses/COMP2000", params: { term_uid: term.uid }

      expect(json["data"]["sections"].pluck("crn")).to eq([ section.crn ])
    end

    it "answers 404 for an unknown course or term" do
      get "/api/v1/catalog/courses/COMP9999"
      expect(response).to have_http_status(:not_found)

      get "/api/v1/catalog/courses/COMP2000", params: { term_uid: 1 }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/catalog/courses" do
    it "finds courses by title words, code, or subject" do
      create(:catalog_course, subject_code: "MATH", course_number: 2860, title: "Linear Algebra")

      get "/api/v1/catalog/courses", params: { q: "data struct" }
      expect(json["data"].pluck("code")).to eq([ "COMP 2000" ])

      get "/api/v1/catalog/courses", params: { q: "MATH 2860" }
      expect(json["data"].pluck("code")).to eq([ "MATH 2860" ])

      get "/api/v1/catalog/courses", params: { subject: "comp", per_page: 1 }
      expect(json["data"].pluck("code")).to eq([ "COMP 1050" ])
      expect(json["meta"]).to include("total_count" => 2, "total_pages" => 2)
    end

    it "lists only the courses offered in a term" do
      create(:course, term: term, subject: "Computer Science (COMP)", course_number: 1050)

      get "/api/v1/catalog/courses", params: { term_uid: term.uid }
      expect(json["data"].pluck("code")).to eq([ "COMP 1050" ])

      get "/api/v1/catalog/courses", params: { term_uid: 1 }
      expect(json["data"]).to eq([])
    end
  end

  describe "section details" do
    it "adds the course description and prerequisites to each section" do
      section = create(:course, term: term, subject: "Computer Science (COMP)", course_number: 2000)
      create(:course, term: term, subject: "Computer Science (COMP)", course_number: 4999)

      get "/api/v1/catalog/sections", params: { term_uid: term.uid }

      by_crn = json["data"].index_by { |s| s["crn"] }
      expect(by_crn[section.crn]["course"]).to include("code" => "COMP 2000", "typically_offered" => %w[fall spring])
      expect(by_crn[section.crn]["course"]["prerequisites"]["type"]).to eq("or")
      expect(by_crn.values.find { |s| s["course_number"] == 4999 }["course"]).to be_nil

      get "/api/v1/catalog/sections/#{section.crn}", params: { term_uid: term.uid }
      expect(json["data"]["course"]["code"]).to eq("COMP 2000")
    end
  end
end
