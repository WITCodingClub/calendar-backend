# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::SemanticBudget do
  let(:request) { ActionDispatch::Request.new(Rack::MockRequest.env_for("/api/mcp", method: "POST")) }

  it "allows a search while the budget lasts" do
    allow(Rack::Attack).to receive(:semantic_search_throttled?).with(request.env).and_return(false)

    expect { described_class.new(request).spend! }.not_to raise_error
  end

  it "refuses a search when the budget is used up" do
    allow(Rack::Attack).to receive(:semantic_search_throttled?).and_return(true)

    expect { described_class.new(request).spend! }.to raise_error(McpTools::ToolError, /Too many semantic searches/)
  end

  it "counts nothing outside a request" do
    allow(Rack::Attack).to receive(:semantic_search_throttled?)

    described_class.new(nil).spend!

    expect(Rack::Attack).not_to have_received(:semantic_search_throttled?)
  end
end
