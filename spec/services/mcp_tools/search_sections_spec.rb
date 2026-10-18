# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::SearchSections do
  let(:user) { create(:user) }
  let(:term) { create(:term) }

  def call(**arguments) = described_class.call(server_context: mcp_context(user), **arguments)

  it "searches one term with the catalog filters" do
    match = create(:course, term: term, subject: "MATH", title: "Calculus")
    create(:course, term: term, subject: "COMP", title: "Programming")
    create(:course, subject: "MATH", title: "Calculus")

    result = call(term_uid: term.uid, subject: [ "MATH" ])

    expect(result.structured_content[:meta][:total_count]).to eq(1)
    expect(result.structured_content[:sections].pluck(:crn)).to eq([ match.crn ])
  end

  it "uses the current term when no term is given" do
    create(:course, term: term)
    allow(Term).to receive(:current).and_return(term)

    expect(call.structured_content[:term_uid]).to eq(term.uid)
  end

  it "pages the results the same as the REST API" do
    create_list(:course, 3, term: term)

    result = call(term_uid: term.uid, page: 2, per_page: 2)

    expect(result.structured_content[:meta]).to eq(page: 2, per_page: 2, total_count: 3, total_pages: 2)
    expect(result.structured_content[:sections].size).to eq(1)
  end

  it "takes the CRN, schedule type, and cancelled filters" do
    cancelled = create(:course, term: term, status: :cancelled)

    expect(call(term_uid: term.uid, crns: [ cancelled.crn ]).structured_content[:sections]).to be_empty
    result = call(term_uid: term.uid, crns: [ cancelled.crn ], schedule_types: [ "lecture" ], include_cancelled: true)
    expect(result.structured_content[:sections].pluck(:crn)).to eq([ cancelled.crn ])
  end

  it "counts a semantic search against the token's budget" do
    budget = instance_double(McpTools::SemanticBudget)
    allow(McpTools::SemanticBudget).to receive(:new).and_return(budget)
    allow(budget).to receive(:spend!).and_raise(McpTools::ToolError, "Too many semantic searches.")

    result = call(term_uid: term.uid, q: "machine learning", semantic: true)

    expect(result.content.first[:text]).to eq("Too many semantic searches.")
  end

  it "does not count a semantic search with no words" do
    allow(McpTools::SemanticBudget).to receive(:new)

    call(term_uid: term.uid, semantic: true)

    expect(McpTools::SemanticBudget).not_to have_received(:new)
  end

  it "returns a tool error for a bad filter value" do
    result = call(term_uid: term.uid, begins_after: "noon")

    expect(result.error?).to be(true)
    expect(result.content.first[:text]).to include("Invalid time")
  end

  it "returns a tool error for an unknown term" do
    result = call(term_uid: 1)

    expect(result.error?).to be(true)
    expect(result.content.first[:text]).to include("No term with uid 1")
  end

  it "returns a tool error when there is no current term" do
    allow(Term).to receive(:current).and_return(nil)

    expect(call.content.first[:text]).to include("There is no current term")
  end
end
