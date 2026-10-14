# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::SearchReviews do
  let(:user) { create(:user) }

  def call(**arguments) = described_class.call(server_context: { user: user }, **arguments)

  it "filters reviews by instructor and words" do
    faculty = create(:faculty)
    match   = create(:rmp_rating, faculty: faculty, comment: "Lots of group projects")
    create(:rmp_rating, faculty: faculty, comment: "Hard exams")
    create(:rmp_rating, comment: "Lots of group projects")

    result = call(instructor_id: faculty.public_id, q: "group")

    expect(result.structured_content[:reviews].size).to eq(1)
    expect(result.structured_content[:reviews].first[:comment]).to eq(match.comment)
    expect(result.structured_content[:meta]).to include(total_count: 1, source: "ratemyprofessors.com")
  end

  it "returns a tool error for an unknown instructor" do
    expect(call(instructor_id: "fac_nope").content.first[:text]).to include("Unknown instructor")
  end
end
