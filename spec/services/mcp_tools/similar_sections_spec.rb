# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::SimilarSections do
  let(:user) { create(:user) }
  let(:term) { create(:term) }

  def call(**arguments) = described_class.call(server_context: mcp_context(user), **arguments)

  it "lists the nearest sections by vector" do
    course = give_embedding(create(:course, term: term), 0.0)
    near   = give_embedding(create(:course, term: term), 0.1)
    far    = give_embedding(create(:course, term: term), 1.0)

    crns = call(crn: course.crn, term_uid: term.uid, limit: 1).structured_content[:sections].pluck(:crn)

    expect(crns).to eq([ near.crn ])
    expect(far.crn).not_to be_in(crns)
  end

  it "returns an empty list for a section with no vector" do
    course = create(:course, term: term)

    expect(call(crn: course.crn, term_uid: term.uid).structured_content[:sections]).to eq([])
  end
end
