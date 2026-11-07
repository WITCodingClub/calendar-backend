# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::MyPrograms, :degree_planning do
  let(:user) { create(:user) }

  def call(scopes: McpTools::Scopes::NAMES) = described_class.call(server_context: mcp_context(user, scopes: scopes))

  it "needs the programs:read scope" do
    create(:student_program, user: user)

    result = call(scopes: %w[catalog schedule:read])

    expect(result.error?).to be(true)
    expect(result.content.first[:text]).to include("Your programs")
  end

  it "is not in a legacy read token, which gives only the read scopes from before the split" do
    expect(call(scopes: McpTools::Scopes.expand("read")).error?).to be(true)
  end

  it "lists the active, planned, and ended programs with the catalog link and the profile" do
    year = create(:catalog_year, :imported, start_year: 2025)
    major = create(:degree_program, slug: "widget-design-bs")
    create(:academic_profile, user: user, level: "Undergraduate", class_standing: "Sophomore")
    active = create(:student_program, user: user, name: "Widget Design", catalog_term_uid: 202610,
                                      degree_program: major, catalog_year: year)
    planned = create(:student_program, :planned, catalog_year: year, user: user, name: "Gear Minor", role: "minor")
    old = create(:student_program, :ended, user: user, name: "Old Major", ended_at: 2.days.ago)
    older = create(:student_program, :ended, user: user, name: "First Major", ended_at: 1.year.ago)
    create(:student_program, :planned, catalog_year: year)

    result = call.structured_content

    expect(result).to include(level: "Undergraduate", class_standing: "Sophomore")
    expect(result[:programs]).to contain_exactly(
      include(id: active.public_id, status: "active", program: "widget-design-bs", catalog_year: "2025-2026",
              catalog_term: "Fall 2025", matched: true)
    )
    expect(result[:planned_programs]).to contain_exactly(include(id: planned.public_id, status: "planned", role: "minor"))
    expect(result[:ended_programs].pluck(:id)).to eq([ old.public_id, older.public_id ])
    expect(result).not_to have_key(:message)
    expect(result[:advisory][:message]).to eq(McpTools::BaseTool::ADVISORY)
  end

  it "says how to add programs when the student has none, and does not guess" do
    result = call.structured_content

    expect(result).to include(programs: [], planned_programs: [], ended_programs: [], level: nil)
    expect(result[:message]).to include("LeopardWeb", "Do not guess")
  end
end
