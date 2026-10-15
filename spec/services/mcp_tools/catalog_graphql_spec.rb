# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::CatalogGraphql do
  let(:user) { create(:user) }

  def call(**arguments) = described_class.call(server_context: mcp_context(user), **arguments)

  it "runs a query on the catalog schema with variables" do
    term = create(:term)
    course = create(:course, term: term)

    result = call(
      query:     "query($crn: Int!, $uid: Int) { section(crn: $crn, termUid: $uid) { crn } }",
      variables: { crn: course.crn, uid: term.uid }
    )

    expect(result.error?).to be(false)
    expect(result.structured_content.dig("data", "section", "crn")).to eq(course.crn)
  end

  it "returns a tool error for a query that does not validate" do
    result = call(query: "{ nope }")

    expect(result.error?).to be(true)
    expect(result.content.first[:text]).to include("nope")
  end

  it "refuses a very long query" do
    expect(call(query: "{#{' ' * 10_001}}").content.first[:text]).to include("longer than")
  end

  it "counts a semantic search against the request's budget" do
    request = ActionDispatch::Request.new(Rack::MockRequest.env_for("/api/mcp", method: "POST"))
    allow(Rack::Attack).to receive(:semantic_search_throttled?).with(request.env).and_return(true)

    result = described_class.call(server_context: mcp_context(user, request: request),
                                  query: '{ instructors(q: "robots", semantic: true) { nodes { name } } }')

    expect(result.content.first[:text]).to include("Rate limit exceeded for semantic search")
  end
end
