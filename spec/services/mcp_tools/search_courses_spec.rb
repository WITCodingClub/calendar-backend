# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::SearchCourses do
  let(:user) { create(:user) }

  it "searches courses and pages the results" do
    create(:catalog_course, subject_code: "COMP", course_number: 2150, title: "Network Administration")
    create(:catalog_course, subject_code: "COMP", course_number: 3500, title: "Network Security")
    create(:catalog_course, subject_code: "MATH", course_number: 2860, title: "Linear Algebra")

    result = described_class.call(server_context: mcp_context(user), q: "network", subject: [ "COMP" ], per_page: 1)

    expect(result.structured_content[:courses].pluck(:code)).to eq([ "COMP 2150" ])
    expect(result.structured_content[:meta]).to include(total_count: 2, total_pages: 2)
  end
end
