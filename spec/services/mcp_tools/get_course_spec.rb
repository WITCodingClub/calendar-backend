# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::GetCourse do
  let(:user) { create(:user) }

  def call(**arguments) = described_class.call(server_context: mcp_context(user), **arguments)

  it "gets a course by code, with sections in a term" do
    term = create(:term)
    create(:catalog_course, :with_details, subject_code: "COMP", course_number: 2350, title: "Algorithms")
    section = create(:course, term: term, subject: "Computer Science (COMP)", course_number: 2350)

    result = call(code: "comp2350", term_uid: term.uid)

    expect(result.structured_content).to include(code: "COMP 2350", title: "Algorithms", typically_offered: %w[fall spring])
    expect(result.structured_content[:sections].pluck(:crn)).to eq([ section.crn ])
  end

  it "gives the catalog entry, fees, learning objectives, and mutual exclusions" do
    create(:catalog_course, subject_code: "ARCH", course_number: 6100, title: "Graduate Studio")
    create(:catalog_course, :with_details, subject_code: "ARCH", course_number: 4100,
                                           college: "School of Architecture and Design", department: "Architecture",
                                           levels: [ "Undergraduate" ], grading_modes: [ "Standard Letter" ],
                                           fees: [ { "level" => "Undergraduate", "description" => "Studio Fee", "amount_cents" => 15_000 } ],
                                           learning_objectives: "Draw a plan.",
                                           mutual_exclusions: [ { "subject_code" => "ARCH", "course_number" => 6100 } ])

    course = call(code: "ARCH 4100").structured_content

    expect(course).to include(college: "School of Architecture and Design", department: "Architecture",
                              levels: [ "Undergraduate" ], grading_modes: [ "Standard Letter" ],
                              learning_objectives: "Draw a plan.")
    expect(course[:fees]).to eq([ { "level" => "Undergraduate", "description" => "Studio Fee", "amount_cents" => 15_000 } ])
    expect(course[:mutual_exclusions]).to contain_exactly(include("code" => "ARCH 6100", "title" => "Graduate Studio", "linked" => true))
  end

  it "returns tool errors for a bad code, an unknown course, or an unknown term" do
    create(:catalog_course, subject_code: "COMP", course_number: 2350)

    expect(call(code: "algorithms").content.first[:text]).to include("is not a course code")
    expect(call(code: "COMP 9999").content.first[:text]).to include("No course COMP 9999")
    expect(call(code: "COMP 2350", term_uid: 1).content.first[:text]).to include("No term with uid 1")
  end
end
