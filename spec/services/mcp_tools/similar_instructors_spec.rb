# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::SimilarInstructors do
  let(:user) { create(:user) }

  def teaching(angle)
    give_embedding(create(:faculty), angle).tap { |faculty| create(:course).faculties << faculty }
  end

  it "lists the nearest instructors who teach, by vector" do
    faculty = teaching(0.0)
    near    = teaching(0.1)

    result = described_class.call(server_context: mcp_context(user), instructor_id: faculty.public_id, limit: 1)

    expect(result.structured_content[:instructor_id]).to eq(faculty.public_id)
    expect(result.structured_content[:instructors].pluck(:pub_id)).to eq([ near.public_id ])
  end
end
