# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::GetSection do
  let(:user) { create(:user) }
  let(:course) { create(:course) }

  def call(**arguments) = described_class.call(server_context: mcp_context(user), **arguments)

  it "gets a section by CRN with its final exam" do
    create(:final_exam, term: course.term, crn: course.crn, course: course)

    result = call(crn: course.crn, term_uid: course.term.uid)

    expect(result.structured_content).to include(crn: course.crn)
    expect(result.structured_content[:final_exam]).to include(date: Date.new(2026, 12, 17))
  end

  it "finds a cancelled section, the same as the REST API" do
    course.update!(status: :cancelled)

    expect(call(crn: course.crn, term_uid: course.term.uid).error?).to be(false)
  end

  it "returns a tool error for an unknown CRN" do
    result = call(crn: 1, term_uid: course.term.uid)

    expect(result.error?).to be(true)
    expect(result.content.first[:text]).to eq("No section with CRN 1 in term #{course.term.uid}")
  end
end
