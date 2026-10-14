# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Catalog GraphQL courses" do
  def execute(query, variables = {})
    CatalogSchema.execute(query, variables: variables, context: {}).to_h
  end

  let(:term) { create(:term) }
  let!(:comp1050) { create(:catalog_course, subject_code: "COMP", course_number: 1050, title: "Computer Science II") }
  let!(:comp2000) do
    create(:catalog_course, :with_details, subject_code: "COMP", course_number: 2000, title: "Data Structures",
                                           prerequisites: { "type" => "course", "subject_code" => "COMP", "course_number" => 1050 })
  end

  before { create(:course_prerequisite, catalog_course: comp2000, required_catalog_course: comp1050) }

  it "finds a course by code, with enriched prerequisites and unlocks" do
    result = execute('{ course(code: "COMP 1050") { code title unlocks { code } } c2: course(code: "COMP2000") { prerequisites typicallyOffered description } }')

    expect(result.dig("data", "course")).to eq("code" => "COMP 1050", "title" => "Computer Science II", "unlocks" => [ { "code" => "COMP 2000" } ])
    expect(result.dig("data", "c2", "prerequisites")).to include("code" => "COMP 1050", "linked" => true)
    expect(result.dig("data", "c2", "typicallyOffered")).to eq(%w[fall spring])
  end

  it "searches courses" do
    result = execute('{ courses(q: "data") { totalCount nodes { code corequisites restrictions } } }')

    expect(result.dig("data", "courses", "nodes")).to eq([ { "code" => "COMP 2000", "corequisites" => [], "restrictions" => [] } ])
  end

  it "adds the course to sections, loading each course once" do
    section = create(:course, term: term, subject: "Computer Science (COMP)", course_number: 2000)
    create(:course, term: term, subject: "Computer Science (COMP)", course_number: 2000)

    result = execute("query($uid: Int!) { sections(filter: { termUid: $uid }) { nodes { crn description prerequisites course { code } } } }",
                     { "uid" => term.uid })

    node = result.dig("data", "sections", "nodes").find { |n| n["crn"] == section.crn }
    expect(node["course"]).to eq("code" => "COMP 2000")
    expect(node["description"]).to eq(comp2000.description)
    expect(node["prerequisites"]).to include("code" => "COMP 1050")
  end
end
