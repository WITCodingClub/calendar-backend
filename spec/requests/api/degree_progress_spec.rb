# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/api/user/degree_progress", :degree_planning, type: :request do
  let(:user) { create(:user) }
  let!(:catalog_year) { create(:catalog_year, :imported, start_year: 2025) }
  let(:major) { create(:degree_program, slug: "widget-design-bs") }

  before do
    set = create(:requirement_set, degree_program: major, catalog_year: catalog_year)
    create(:program_plan_item, program_plan: create(:program_plan, requirement_set: set), subject_code: "WDGT", course_number: 1000)
  end

  it "returns the same data as the my_degree_progress tool" do
    create(:student_program, user: user, degree_program: major, catalog_year: catalog_year)

    get "/api/user/degree_progress", headers: auth_headers_for(user)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["programs"].first["summary"]).to include("credits" => { "earned" => 0, "in_progress" => 0, "not_counted" => { "earned" => 0, "in_progress" => 0, "courses" => [] } })
    expect(response.parsed_body["programs"].first["requirements"].first).to include("title" => nil, "list" => nil)
    tool = McpTools::MyDegreeProgress.call(server_context: mcp_context(user)).structured_content.except(:advisory)
    expect(response.parsed_body).to eq(JSON.parse(tool.to_json))
  end

  it "checks a program the student names" do
    get "/api/user/degree_progress", params: { program: "widget-design-bs", catalog_year: "2025-2026" }, headers: auth_headers_for(user)

    expect(response.parsed_body["programs"].first).to include("program" => "widget-design-bs", "catalog_year" => "2025-2026")
  end

  it "also checks the planned programs with include_planned" do
    minor = create(:degree_program, :minor, slug: "gear-minor")
    group = create(:elective_group, requirement_set: create(:requirement_set, degree_program: minor, catalog_year: catalog_year),
                                    name: "Gear Electives", min_courses: 1)
    create(:elective_group_course, elective_group: group, subject_code: "GEAR", course_number: 2000)
    create(:student_program, user: user, degree_program: major, catalog_year: catalog_year)
    create(:student_program, :planned, user: user, degree_program: minor, catalog_year: catalog_year)

    get "/api/user/degree_progress", headers: auth_headers_for(user)
    expect(response.parsed_body["programs"].pluck("program", "status")).to eq([ [ "widget-design-bs", "active" ] ])

    get "/api/user/degree_progress", params: { include_planned: "true" }, headers: auth_headers_for(user)
    expect(response.parsed_body["programs"].pluck("program", "status"))
      .to eq([ [ "widget-design-bs", "active" ], [ "gear-minor", "planned" ] ])
    planned = response.parsed_body["programs"].last
    # The major plan has no elective slot, so the course has no slot (#998).
    expect(planned["overlap"]).to include("shared" => 0, "extra" => 1, "slots" => [], "unplaced" => 1,
                                          "expected_end_with_minor" => anything)
    expect(planned["lists"].sole).to include("name" => "Gear Electives", "min_courses" => 1,
                                             "courses" => [ include("code" => "GEAR 2000", "status" => "open", "major_term" => nil) ])
  end

  it "answers 422 with no_program when the student has no linked program, and for bad params" do
    get "/api/user/degree_progress", headers: auth_headers_for(user)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["code"]).to eq("no_program")

    get "/api/user/degree_progress", params: { catalog_year: "2025-2026" }, headers: auth_headers_for(user)
    expect(response.parsed_body["error"]).to eq("catalog_year and plan need program")

    get "/api/user/degree_progress", params: { plan: "Three Year Program" }, headers: auth_headers_for(user)
    expect(response.parsed_body["error"]).to eq("catalog_year and plan need program")

    get "/api/user/degree_progress", params: { program: "basket-weaving-bs" }, headers: auth_headers_for(user)
    expect(response).to have_http_status(:unprocessable_content)

    get "/api/user/degree_progress", params: { program: "widget-design-bs", plan: [ "x" ] }, headers: auth_headers_for(user)
    expect(response).to have_http_status(:unprocessable_content)
  end
end
