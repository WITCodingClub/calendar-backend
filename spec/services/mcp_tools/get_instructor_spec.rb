# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::GetInstructor do
  let(:user) { create(:user) }

  def call(id) = described_class.call(server_context: mcp_context(user), instructor_id: id)

  it "gets an instructor by public id" do
    faculty = create(:faculty)

    expect(call(faculty.public_id).structured_content).to include(pub_id: faculty.public_id)
  end

  it "returns a tool error for an unknown id" do
    expect(call("fac_nope").content.first[:text]).to include("No instructor fac_nope")
  end

  it "includes the Rate My Professors details and the sections in a term" do
    term = create(:term)
    faculty = create(:faculty)
    create(:teacher_rating_tag, faculty: faculty, tag_name: "Caring", tag_count: 3)
    create(:course, term: term).faculties << faculty

    result = described_class.call(server_context: mcp_context(user), instructor_id: faculty.public_id, term_uid: term.uid)

    expect(result.structured_content[:rmp_tags]).to eq([ { name: "Caring", count: 3 } ])
    expect(result.structured_content[:sections].size).to eq(1)
  end

  it "returns a tool error for an unknown term" do
    faculty = create(:faculty)

    expect(described_class.call(server_context: mcp_context(user), instructor_id: faculty.public_id, term_uid: 1).error?).to be(true)
  end
end
