# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Catalog term electives API", type: :request do
  def json = response.parsed_body

  let(:term) { create(:term) }
  let!(:list) do
    create(:term_elective_list, term: term, school: "SCDS", title: "Computing Electives",
                                body_text: "Any 2000-Level courses in COMP")
  end

  before do
    create(:catalog_course, subject_code: "COMP", course_number: 2000, title: "Data Structures")
    create(:term_elective_course, term_elective_list: list, subject_code: "COMP", course_number: 2000, heading: "Computer Science Elective")
    create(:term_elective_course, term_elective_list: list, subject_code: "MATH", course_number: 4050, heading: "NET Elective")
    TermElectiveCourse.link_catalog_courses
  end

  it "lists the elective lists of the term with their courses and text" do
    get "/api/v1/catalog/terms/#{term.uid}/electives"

    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to eq("max-age=3600, public")
    expect(json["meta"]).to eq("count" => 1, "term_uid" => term.uid, "term" => term.name)
    expect(json["data"].first).to include("school" => "SCDS", "title" => "Computing Electives", "url" => list.url,
                                          "text" => "Any 2000-Level courses in COMP")
    expect(json["data"].first["courses"]).to eq([
      { "code" => "COMP 2000", "title" => "Data Structures", "heading" => "Computer Science Elective" },
      { "code" => "MATH 4050", "title" => nil, "heading" => "NET Elective" }
    ])
  end

  it "filters by school, course, and heading words" do
    get "/api/v1/catalog/terms/#{term.uid}/electives", params: { school: "SCDS,HSS", course: "MATH4050", q: "net" }

    expect(json["data"].first["courses"].pluck("code")).to eq([ "MATH 4050" ])
  end

  it "answers 400 for a bad filter" do
    get "/api/v1/catalog/terms/#{term.uid}/electives", params: { school: "XYZ" }

    expect(response).to have_http_status(:bad_request)
    expect(json["code"]).to eq("INVALID_FILTER")
  end

  it "answers 400 for words or a course given as a list" do
    get "/api/v1/catalog/terms/#{term.uid}/electives", params: { q: [ "net" ] }

    expect(response).to have_http_status(:bad_request)
    expect(json["error"]).to eq("q must be one value")
  end

  it "answers 404 for an unknown term" do
    get "/api/v1/catalog/terms/999999/electives"

    expect(response).to have_http_status(:not_found)
    expect(json["error"]).to eq("No term 999999")
  end
end
