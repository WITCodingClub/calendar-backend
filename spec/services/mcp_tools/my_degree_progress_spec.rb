# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::MyDegreeProgress do
  let(:user) { create(:user) }
  let!(:catalog_year) { create(:catalog_year, :imported, start_year: 2025) }
  let(:major) { create(:degree_program, slug: "widget-design-bs") }

  def call(scopes: McpTools::Scopes::NAMES, **arguments)
    described_class.call(server_context: mcp_context(user, scopes: scopes), **arguments)
  end

  def text(result) = result.content.first[:text]

  it "needs the programs:read scope, which a legacy read token does not have" do
    result = call(scopes: McpTools::Scopes.expand("read"))

    expect(result.error?).to be(true)
    expect(text(result)).to include("Your programs")
  end

  it "says in its description that it is not the official audit" do
    expect(described_class.description_value).to include("not a degree audit", "Stellic")
  end

  it "gives the progress of the student's programs with the advisory" do
    set = create(:requirement_set, degree_program: major, catalog_year: catalog_year)
    create(:program_plan_item, program_plan: create(:program_plan, requirement_set: set), subject_code: "WDGT", course_number: 1000)
    create(:student_program, user: user, degree_program: major, catalog_year: catalog_year)

    result = call.structured_content

    expect(result[:programs].first).to include(program: "widget-design-bs", counts: { "done" => 0, "in_progress" => 0, "open" => 1 })
    expect(result[:advisory][:data_sources].pluck(:key)).to eq(%w[degree_requirements sections])
  end

  it "answers with a tool error that says how to add a program, and for a bad argument" do
    expect(text(call)).to include("process a term", "pass program and catalog_year")
    expect(text(call(catalog_year: "2025-2026"))).to include("catalog_year needs program")
    expect(text(call(program: "basket-weaving-bs"))).to include("No program basket-weaving-bs")
    expect(text(call(program: "widget-design-bs", catalog_year: "someday"))).to include("catalog_year must be")
  end
end
