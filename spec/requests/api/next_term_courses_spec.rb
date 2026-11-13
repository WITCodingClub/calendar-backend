# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/api/user/next_term_courses", :degree_planning, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let!(:catalog_year) { create(:catalog_year, :imported, start_year: 2025) }
  let(:major) { create(:degree_program, slug: "widget-design-bs") }

  before do
    set = create(:requirement_set, degree_program: major, catalog_year: catalog_year)
    create(:program_plan_item, program_plan: create(:program_plan, requirement_set: set), year_index: 2, season: "spring",
                               subject_code: "WDGT", course_number: 2000)
  end

  it "returns the same data as the my_next_term_courses tool" do
    create(:student_program, user: user, degree_program: major, catalog_year: catalog_year, catalog_term_uid: 202610)

    get "/api/user/next_term_courses", params: { term: "202720" }, headers: auth_headers_for(user)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("programs", 0, "planned", 0, "code")).to eq("WDGT 2000")
    tool = McpTools::MyNextTermCourses.call(server_context: mcp_context(user), term: "Spring 2027").structured_content
    expect(response.parsed_body).to eq(JSON.parse(tool.except(:advisory).to_json))
  end

  it "uses the next fall or spring term without a term" do
    create(:student_program, user: user, degree_program: major, catalog_year: catalog_year, catalog_term_uid: 202610)
    create(:term, uid: 202710, year: 2026, season: :fall, start_date: Date.new(2026, 9, 1), end_date: Date.new(2026, 12, 20))

    travel_to Date.new(2026, 11, 6) do
      get "/api/user/next_term_courses", headers: auth_headers_for(user)
    end

    expect(response.parsed_body["term"]).to eq("uid" => 202720, "name" => "Spring 2027")
  end

  it "counts the courses of a saved plan before the term with assume_plans, and the tool does the same (#996)" do
    create(:student_program, user: user, degree_program: major, catalog_year: catalog_year, catalog_term_uid: 202610)
    create(:term, uid: 202710, year: 2026, season: :fall, start_date: Date.new(2026, 9, 1), end_date: Date.new(2026, 12, 20))
    spring = create(:term, uid: 202720, year: 2027, season: :spring)
    create(:registration_plan, user: user, term: spring, courses: [ { "code" => "WDGT 2000", "crns" => [ "20410" ] } ])
    tool = travel_to Date.new(2026, 11, 6) do
      get "/api/user/next_term_courses", params: { term: "202810", assume_plans: "true", assume: "WDGT1000" },
                                         headers: auth_headers_for(user)
      McpTools::MyNextTermCourses.call(server_context: mcp_context(user), term: "202810", assume_plans: true,
                                       assume: [ "WDGT1000" ]).structured_content
    end

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["assumed"]).to eq("courses" => [ "WDGT 1000", "WDGT 2000" ], "from_plans" => [ 202720 ])
    expect(response.parsed_body).to eq(JSON.parse(tool.except(:advisory).to_json))
  end

  it "takes assume as a list" do
    create(:student_program, user: user, degree_program: major, catalog_year: catalog_year, catalog_term_uid: 202610)

    get "/api/user/next_term_courses", params: { term: "202720", assume: [ "WDGT1000", "WDGT 1100" ] },
                                       headers: auth_headers_for(user)

    expect(response.parsed_body["assumed"]).to eq("courses" => [ "WDGT 1000", "WDGT 1100" ], "from_plans" => [])
  end

  it "answers 422 for an assume value that is not a course code" do
    create(:student_program, user: user, degree_program: major, catalog_year: catalog_year, catalog_term_uid: 202610)

    get "/api/user/next_term_courses", params: { assume: "WDGT1000,Widgets" }, headers: auth_headers_for(user)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to eq("assume must be course codes such as COMP3350, separated by commas")
  end

  it "answers 422 with no_program when the student has no linked program, and for a bad term" do
    get "/api/user/next_term_courses", headers: auth_headers_for(user)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["code"]).to eq("no_program")

    get "/api/user/next_term_courses", params: { term: "Winter 2027" }, headers: auth_headers_for(user)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to include("Banner term code")
  end
end
