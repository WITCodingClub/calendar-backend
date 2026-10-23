# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::GetDegreeRequirements do
  let(:user) { create(:user) }
  let!(:catalog_year) { create(:catalog_year, :imported, start_year: 2024) }
  let(:major) { create(:degree_program, slug: "widget-design-bs", name: "Widget Design, B.S.") }
  let!(:set) { create(:requirement_set, degree_program: major, catalog_year: catalog_year, name: "Widget Design, B.S.") }

  def call(**arguments) = described_class.call(server_context: mcp_context(user), **arguments)

  def text(result) = result.content.first[:text]

  it "is named degree_requirements" do
    expect(described_class.name_value).to eq("degree_requirements")
  end

  it "gets a program by slug or by name, with its plans" do
    plan = create(:program_plan, requirement_set: set, name: "Three Year Program", years: 3, accelerated: true)
    create(:program_plan_item, program_plan: plan, subject_code: "WDGT", course_number: 1000)

    by_slug = call(program: "widget-design-bs").structured_content
    by_name = call(program: "widget design, b.s.", catalog_year: "2024-2025").structured_content

    expect(by_slug[:plans].first).to include(name: "Three Year Program", years: 3, accelerated: true)
    expect(by_slug[:plans].first[:terms].first[:items].first).to include(code: "WDGT 1000")
    expect(by_name.except(:advisory)).to eq(by_slug.except(:advisory))
  end

  it "returns tool errors for an unknown program or catalog year" do
    expect(text(call(program: "basket-weaving-bs"))).to include("No program basket-weaving-bs in the 2024-2025 catalog",
                                                                "list_programs")
    expect(text(call(program: "widget-design-bs", catalog_year: "2016"))).to include("No 2016 catalog")
  end
end
