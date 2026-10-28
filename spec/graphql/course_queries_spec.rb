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

  it "gives the seat and waitlist counts of a section" do
    create(:course, term: term, seats_capacity: 25, seats_available: 0, waitlist_capacity: 5, waitlist_available: 1)

    result = execute("query($uid: Int!) { sections(filter: { termUid: $uid }) { nodes { seats { capacity available } waitlist { capacity available } } } }",
                     { "uid" => term.uid })

    expect(result.dig("data", "sections", "nodes")).to eq([ { "seats"    => { "capacity" => 25, "available" => 0 },
                                                             "waitlist" => { "capacity" => 5, "available" => 1 } } ])
  end

  it "returns the catalog entry, mutual exclusions, fees, and learning objectives of a course" do
    comp2000.update!(college: "The School of Comp & Data Sci", levels: [ "Undergraduate" ], grading_modes: [ "Standard Letter" ],
                     mutual_exclusions: [ { "subject_code" => "COMP", "course_number" => 1050 } ],
                     fees: [ { "level" => "Undergraduate", "description" => "Follett Access", "amount_cents" => 9499 } ],
                     learning_objectives: "Explain hashing.")

    result = execute('{ course(code: "COMP 2000") { college division levels gradingModes mutualExclusions learningObjectives ' \
                     "fees { level description amountCents } } }")

    expect(result.dig("data", "course")).to include(
      "college" => "The School of Comp & Data Sci", "division" => nil, "levels" => [ "Undergraduate" ],
      "gradingModes" => [ "Standard Letter" ], "learningObjectives" => "Explain hashing.",
      "fees" => [ { "level" => "Undergraduate", "description" => "Follett Access", "amountCents" => 9499 } ]
    )
    expect(result.dig("data", "course", "mutualExclusions").first).to include("code" => "COMP 1050", "linked" => true)
  end

  it "returns the part of term, campus, and cross-list group of a section" do
    section = create(:course, :cross_listed, term: term, part_of_term: "FA2", campus: "Online Course")
    partner = create(:course, :cross_listed, term: term)

    result = execute("query($uid: Int!) { sections(filter: { termUid: $uid }) { nodes { crn partOfTerm campus " \
                     "crossList { identifier crns seats { capacity available } } } } }", { "uid" => term.uid })

    node = result.dig("data", "sections", "nodes").find { |n| n["crn"] == section.crn }
    expect(node).to include("partOfTerm" => "FA2", "campus" => "Online Course")
    expect(node["crossList"]).to eq("identifier" => "01", "crns" => [ partner.crn ], "seats" => { "capacity" => 24, "available" => 4 })
  end
end
