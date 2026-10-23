# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::ListPrograms do
  let(:user) { create(:user) }
  let!(:older) { create(:catalog_year, :imported, start_year: 2023) }
  let!(:newer) { create(:catalog_year, :imported, start_year: 2024) }

  def call(**arguments) = described_class.call(server_context: mcp_context(user), **arguments)

  def text(result) = result.content.first[:text]

  before do
    major = create(:degree_program, slug: "widget-design-bs", name: "Widget Design, B.S.")
    create(:requirement_set, degree_program: major, catalog_year: newer, name: "Widget Design, B.S.")
    create(:requirement_set, degree_program: major, catalog_year: older, name: "Widget Design Bachelor of Science")
    minor = create(:degree_program, :minor, slug: "gear-minor", name: "Gear Minor")
    create(:requirement_set, degree_program: minor, catalog_year: newer, name: "Gear Minor")
  end

  it "lists the programs of the newest catalog year, and the catalog years" do
    result = call

    expect(result.structured_content).to include(catalog_year: "2024-2025", catalog_years: %w[2024-2025 2023-2024])
    expect(result.structured_content[:programs].pluck(:slug)).to eq(%w[gear-minor widget-design-bs])
    expect(result.structured_content[:advisory][:message]).to include("academic advisor")
  end

  it "takes a catalog year, a kind, and words" do
    expect(call(catalog_year: "2023").structured_content[:programs].pluck(:name)).to eq([ "Widget Design Bachelor of Science" ])
    expect(call(kind: "minor").structured_content[:programs].pluck(:slug)).to eq(%w[gear-minor])
    expect(call(q: "widget").structured_content[:programs].pluck(:slug)).to eq(%w[widget-design-bs])
  end

  it "returns tool errors for a year that is not imported or a bad filter" do
    expect(text(call(catalog_year: "2015-2016"))).to include("No 2015-2016 catalog", "2024-2025, 2023-2024")
    expect(text(call(catalog_year: "soon"))).to include("catalog_year must be a year")
    expect(text(call(kind: "doctorate"))).to include("kind must be one of")
  end

  it "says when no catalog year is imported" do
    CatalogYear.update_all(status: "pending")

    expect(text(call)).to include("no degree program data yet")
  end
end
