# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/api/user/programs, /api/user/planned_programs, and /api/user/planned_pathways", type: :request do
  let(:user) { create(:user) }
  let!(:catalog_year) { create(:catalog_year, :imported, start_year: 2026) }
  let(:minor) { create(:degree_program, :minor, slug: "gear-minor", name: "Gear Minor") }

  before { create(:requirement_set, degree_program: minor, catalog_year: catalog_year, name: "Gear Minor") }

  describe "GET /api/user/programs" do
    it "returns the active, planned, and ended programs of the user only" do
      active = create(:student_program, user: user)
      planned = create(:student_program, :planned, catalog_year: catalog_year, user: user, degree_program: minor)
      ended = create(:student_program, :ended, user: user)
      create(:student_program)

      get "/api/user/programs", headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["programs"].pluck("id")).to eq([ active.public_id ])
      expect(body["planned_programs"]).to contain_exactly(include("id" => planned.public_id, "program" => "gear-minor",
                                                                  "catalog_year" => "2026-2027", "status" => "planned"))
      expect(body["ended_programs"].pluck("id")).to eq([ ended.public_id ])
    end

    it "returns the plan and the start term of each program" do
      create(:academic_profile, user: user, admit_term_uid: 202610)
      major = create(:degree_program, slug: "widget-design-bs")
      set = create(:requirement_set, degree_program: major, catalog_year: catalog_year)
      create(:program_plan, requirement_set: set)
      create(:program_plan, :accelerated, requirement_set: set)
      create(:student_program, user: user, degree_program: major, catalog_year: catalog_year, catalog_term_uid: nil,
                               plan_name: "Three Year Program")

      get "/api/user/programs", headers: auth_headers_for(user)

      expect(response.parsed_body["programs"].sole).to include(
        "plan" => "Three Year Program", "plan_source" => "student", "plans" => [ "Four Year Program", "Three Year Program" ],
        "start_term" => "Fall 2025", "start_term_source" => "admit_term"
      )
    end

    it "returns the same data as the my_programs tool" do
      create(:student_program, user: user)

      get "/api/user/programs", headers: auth_headers_for(user)

      tool = McpTools::MyPrograms.call(server_context: mcp_context(user)).structured_content.except(:advisory)
      expect(response.parsed_body).to eq(JSON.parse(tool.to_json))
    end
  end

  describe "POST /api/user/planned_programs" do
    it "adds a planned program" do
      post "/api/user/planned_programs", params: { program: "gear-minor" }, headers: auth_headers_for(user), as: :json

      expect(response).to have_http_status(:created)
      row = user.student_programs.sole
      expect(row).to have_attributes(status: "planned", role: "minor", source: "student")
      expect(response.parsed_body).to include("id" => row.public_id, "program" => "gear-minor", "status" => "planned")
    end

    it "answers 422 with a code for a missing, unknown, or duplicate program" do
      headers = auth_headers_for(user)

      post "/api/user/planned_programs", params: {}, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("error" => "program is required", "code" => "invalid_profile")

      post "/api/user/planned_programs", params: { program: "basket-weaving-bs" }, headers: headers, as: :json
      expect(response.parsed_body["code"]).to eq("unknown_program")

      post "/api/user/planned_programs", params: { program: "gear-minor", catalog_year: "2016-2017" }, headers: headers, as: :json
      expect(response.parsed_body["code"]).to eq("unknown_catalog_year")

      create(:student_program, :minor, user: user, degree_program: minor)
      post "/api/user/planned_programs", params: { program: "gear-minor" }, headers: headers, as: :json
      expect(response.parsed_body["code"]).to eq("duplicate_program")
    end
  end

  describe "DELETE /api/user/planned_programs/:id" do
    it "removes a planned program by public id or slug" do
      row = create(:student_program, :planned, catalog_year: catalog_year, user: user, degree_program: minor)

      delete "/api/user/planned_programs/#{row.public_id}", headers: auth_headers_for(user)

      expect(response).to have_http_status(:no_content)
      expect(StudentProgram.exists?(row.id)).to be(false)

      create(:student_program, :planned, catalog_year: catalog_year, user: user, degree_program: minor)
      delete "/api/user/planned_programs/gear-minor", headers: auth_headers_for(user)
      expect(response).to have_http_status(:no_content)
      expect(user.student_programs).to be_empty
    end

    it "answers 404 for a LeopardWeb program and for another user's planned program" do
      active = create(:student_program, user: user)
      other = create(:student_program, :planned, catalog_year: catalog_year)

      delete "/api/user/planned_programs/#{active.public_id}", headers: auth_headers_for(user)
      expect(response).to have_http_status(:not_found)

      delete "/api/user/planned_programs/#{other.public_id}", headers: auth_headers_for(user)
      expect(response).to have_http_status(:not_found)
      expect(StudentProgram.where(id: [ active.id, other.id ]).count).to eq(2)
    end
  end

  describe "/api/user/planned_pathways" do
    let(:bachelor) { create(:degree_program, slug: "gear-studies-bs", name: "Gear Studies, B.S.") }
    let(:master) { create(:degree_program, :master, slug: "gear-studies-ms", name: "Gear Studies, M.S.") }

    before do
      pathway = create(:program_pathway, slug: "gear-studies-4-plus-1", name: "Gear Studies 4+1", kind: "four_plus_one")
      create(:program_pathway_step, program_pathway: pathway, degree_program: bachelor, position: 1, plan_years: 4)
      create(:program_pathway_step, program_pathway: pathway, degree_program: master, position: 2, plan_years: 1)
      create(:requirement_set, degree_program: bachelor, catalog_year: catalog_year, name: "Gear Studies, B.S.")
      create(:requirement_set, degree_program: master, catalog_year: catalog_year, name: "Gear Studies, M.S.")
    end

    it "adds the missing programs of a pathway, shows the pathway in GET programs, and removes only its rows" do
      active = create(:student_program, user: user, degree_program: bachelor)
      headers = auth_headers_for(user)

      post "/api/user/planned_pathways", params: { pathway: "gear-studies-4-plus-1" }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      row = user.student_programs.planned.sole
      expect(response.parsed_body).to include(
        "pathway"  => include("id" => "gear-studies-4-plus-1", "kind" => "four_plus_one", "max_shared_courses" => 2,
                              "steps" => [ { "program" => "gear-studies-bs", "plan_years" => 4 },
                                           { "program" => "gear-studies-ms", "plan_years" => 1 } ]),
        "programs" => [ include("id" => row.public_id, "program" => "gear-studies-ms", "pathway" => "gear-studies-4-plus-1") ]
      )

      get "/api/user/programs", headers: headers
      expect(response.parsed_body["planned_pathways"].pluck("id")).to eq([ "gear-studies-4-plus-1" ])

      delete "/api/user/planned_pathways/gear-studies-4-plus-1", headers: headers
      expect(response).to have_http_status(:no_content)
      expect(user.student_programs.reload).to eq([ active ])
    end

    it "adds every program of a pathway for a student with no programs" do
      post "/api/user/planned_pathways", params: { pathway: "gear-studies-4-plus-1" }, headers: auth_headers_for(user), as: :json

      expect(response).to have_http_status(:created)
      expect(user.student_programs.planned.map(&:degree_program)).to contain_exactly(bachelor, master)
    end

    it "answers 422 for an unknown pathway and 404 for a pathway the student did not plan" do
      headers = auth_headers_for(user)

      post "/api/user/planned_pathways", params: { pathway: "nope" }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["code"]).to eq("unknown_pathway")

      delete "/api/user/planned_pathways/gear-studies-4-plus-1", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
