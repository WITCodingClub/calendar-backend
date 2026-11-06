# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/api/user/curriculum_graph", type: :request do
  let(:user) { create(:user) }
  let!(:catalog_year) { create(:catalog_year, :imported, start_year: 2025) }
  let(:major) { create(:degree_program, slug: "widget-design-bs") }

  before do
    set = create(:requirement_set, degree_program: major, catalog_year: catalog_year)
    create(:program_plan_item, program_plan: create(:program_plan, requirement_set: set), subject_code: "WDGT", course_number: 1000)
    create(:catalog_course, subject_code: "WDGT", course_number: 1000, title: "Intro to Widgets")
  end

  it "returns the student's plan by semester with a focus course" do
    create(:student_program, user: user, degree_program: major, catalog_year: catalog_year)

    get "/api/user/curriculum_graph", params: { focus: "WDGT1000" }, headers: auth_headers_for(user)

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body).to include("program" => "widget-design-bs", "next_semester" => { "year" => 1, "season" => "fall", "label" => "Year 1 Fall" })
    expect(body["semesters"].first["nodes"].first).to include("code" => "WDGT 1000", "status" => "open")
    expect(body["focus"]).to include("code" => "WDGT 1000", "before" => [], "after" => [])
  end

  it "answers 422 with no_program when the student has no linked program, and for bad params" do
    get "/api/user/curriculum_graph", headers: auth_headers_for(user)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["code"]).to eq("no_program")

    get "/api/user/curriculum_graph", params: { plan: "Three Year Program" }, headers: auth_headers_for(user)
    expect(response.parsed_body["error"]).to eq("catalog_year and plan need program")

    get "/api/user/curriculum_graph", params: { program: "widget-design-bs", focus: "ZZZZ9999" }, headers: auth_headers_for(user)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to eq("No course ZZZZ9999 in WIT Calendar")
  end
end
