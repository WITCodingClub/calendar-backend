# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Catalog programs API", type: :request do
  def json = response.parsed_body

  let!(:older) { create(:catalog_year, :imported, start_year: 2023) }
  let!(:newer) { create(:catalog_year, :imported, start_year: 2024) }
  let(:program) { create(:degree_program, slug: "widget-design-bs", name: "Widget Design, B.S.") }
  let!(:set) do
    create(:requirement_set, degree_program: program, catalog_year: newer, name: "Widget Design, B.S.",
                             school_name: "School of Widgetry", path: "/previous-catalogs/2024-2025/widgetry/widget-design-bs/")
  end

  before do
    create(:requirement_set, degree_program: create(:degree_program, :minor, name: "Gear Minor", slug: "gear-minor"),
                             catalog_year: newer, name: "Gear Minor")
    create(:requirement_set, degree_program: program, catalog_year: older, name: "Widget Design Bachelor of Science")
    create(:catalog_year, start_year: 2030, status: "missing")
    create(:requirement_set, :unlisted, catalog_year: newer, name: "Old Widgets, B.S.",
                                        degree_program: create(:degree_program, slug: "old-widgets-bs"))
  end

  describe "GET /api/v1/catalog/programs" do
    it "lists the programs of the newest imported catalog year" do
      get "/api/v1/catalog/programs"

      expect(response).to have_http_status(:ok)
      expect(json["data"].pluck("slug")).to eq(%w[gear-minor widget-design-bs])
      expect(json["meta"]).to eq("count" => 2, "catalog_year" => "2024-2025", "catalog_years" => %w[2024-2025 2023-2024])
      expect(json["data"].last).to include("name" => "Widget Design, B.S.", "kind" => "bachelor", "level" => "undergraduate", "listed" => true,
                                           "school" => "School of Widgetry", "catalog_year" => "2024-2025",
                                           "catalog_url" => "https://catalog.wit.edu/previous-catalogs/2024-2025/widgetry/widget-design-bs/")
      expect(response.headers["Cache-Control"]).to eq("max-age=3600, public")
    end

    it "filters by catalog year, kind, and words" do
      get "/api/v1/catalog/programs", params: { catalog_year: "2023-2024" }
      expect(json["data"].pluck("name")).to eq([ "Widget Design Bachelor of Science" ])

      get "/api/v1/catalog/programs", params: { kind: "minor" }
      expect(json["data"].pluck("slug")).to eq(%w[gear-minor])

      get "/api/v1/catalog/programs", params: { q: "widget design" }
      expect(json["data"].pluck("slug")).to eq(%w[widget-design-bs])
    end

    it "rejects an unknown kind or a catalog year that is not a year" do
      get "/api/v1/catalog/programs", params: { kind: "doctorate" }
      expect(response).to have_http_status(:bad_request)
      expect(json["code"]).to eq("INVALID_FILTER")

      get "/api/v1/catalog/programs", params: { catalog_year: "last year" }
      expect(response).to have_http_status(:bad_request)
    end

    it "answers 404 for a catalog year that is not imported" do
      get "/api/v1/catalog/programs", params: { catalog_year: 2030 }

      expect(response).to have_http_status(:not_found)
      expect(json["error"]).to eq("No catalog year 2030")
    end
  end

  describe "GET /api/v1/catalog/programs/:slug" do
    before do
      create(:catalog_course, subject_code: "WDGT", course_number: 1000, title: "Widgets I")
      create(:catalog_year_course, catalog_year: newer, subject_code: "WDGT", course_number: 3000, title: "SPINNING")
      plan = create(:program_plan, requirement_set: set, name: "Four Year Program", years: 4, position: 0)
      group = create(:elective_group, requirement_set: set, name: "Widget Electives", min_courses: 2, position: 0)
      create(:elective_group_course, elective_group: group, subject_code: "WDGT", course_number: 3000, requires_approval: true)
      create(:program_plan_item, program_plan: plan, position: 0, subject_code: "WDGT", course_number: 1000, label: "WIDGETS I")
      create(:program_plan_item, :placeholder, program_plan: plan, position: 1, label: "Widget Elective",
                                               elective_group: group, footnote: "1")
      create(:program_plan_item, :choice, program_plan: plan, position: 2, year_index: 2, season: "spring")
    end

    it "returns the plans by year and semester, and the elective lists" do
      get "/api/v1/catalog/programs/widget-design-bs"

      expect(response).to have_http_status(:ok)
      data = json["data"]
      plan = data["plans"].first
      expect(plan).to include("name" => "Four Year Program", "years" => 4, "accelerated" => false)
      expect(plan["terms"].map { |term| [ term["year"], term["season"], term["items"].size ] }).to eq([ [ 1, "fall", 2 ], [ 2, "spring", 1 ] ])
      expect(plan["terms"].first["items"]).to eq([
        { "kind" => "course", "code" => "WDGT 1000", "title" => "Widgets I", "min_credits" => 4, "max_credits" => 4,
          "footnote" => nil, "options" => [], "elective_list" => nil },
        { "kind" => "placeholder", "code" => nil, "title" => "Widget Elective", "min_credits" => 4, "max_credits" => 4,
          "footnote" => "1", "options" => [], "elective_list" => "Widget Electives" }
      ])
      expect(plan["terms"].last["items"].first["options"].pluck("code")).to eq([ "COMP 1000", "COMP 1099" ])
      expect(data["elective_lists"]).to eq([
        { "name" => "Widget Electives", "heading" => set.elective_groups.first.heading, "plan" => nil, "min_courses" => 2,
          "min_credits" => nil, "notes" => nil,
          "courses" => [ { "code" => "WDGT 3000", "title" => "SPINNING", "requires_approval" => true } ] }
      ])
    end

    it "finds a program by its exact name, the same as the MCP tool" do
      get "/api/v1/catalog/programs/#{ERB::Util.url_encode('widget design, b.s.')}"

      expect(response).to have_http_status(:ok)
      expect(json["data"]["slug"]).to eq("widget-design-bs")
    end

    it "loads a program with many linked placeholders in a fixed number of queries" do
      plan = set.program_plans.first
      group = set.elective_groups.first
      3.times { |i| create(:program_plan_item, :placeholder, program_plan: plan, position: 10 + i, elective_group: group) }

      get "/api/v1/catalog/programs/widget-design-bs"

      expect(json["data"]["plans"].first["terms"].first["items"].pluck("elective_list").compact.size).to eq(4)
    end

    it "keeps Banner's title when the catalog year has a row with no title" do
      create(:catalog_course, subject_code: "WDGT", course_number: 3000, title: "Spinning")
      CatalogYearCourse.find_by!(course_number: 3000).update!(title: nil)

      get "/api/v1/catalog/programs/widget-design-bs"

      expect(json["data"]["elective_lists"].first["courses"].first["title"]).to eq("Spinning")
    end

    it "finds a program in an older catalog year" do
      get "/api/v1/catalog/programs/widget-design-bs", params: { catalog_year: 2023 }

      expect(json["data"]).to include("name" => "Widget Design Bachelor of Science", "catalog_year" => "2023-2024", "plans" => [])
    end

    it "answers 404 for a program that is not in the catalog year" do
      get "/api/v1/catalog/programs/gear-minor", params: { catalog_year: 2023 }

      expect(response).to have_http_status(:not_found)
      expect(json["error"]).to eq("No program gear-minor in the 2023-2024 catalog")
    end
  end
end
