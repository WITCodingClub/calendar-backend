# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::SearchInstructors do
  let(:user) { create(:user) }

  def call(**arguments) = described_class.call(server_context: mcp_context(user), **arguments)

  def teaching(**attributes)
    create(:faculty, **attributes).tap { |faculty| create(:course).faculties << faculty }
  end

  it "matches every word of the name" do
    ada = teaching(first_name: "Ada", last_name: "Lovelace")
    teaching(first_name: "Ada", last_name: "Byron")

    result = call(q: "ada love")

    expect(result.structured_content[:instructors].pluck(:pub_id)).to eq([ ada.public_id ])
    expect(result.structured_content[:meta]).to include(total_count: 1, page: 1)
  end

  it "leaves out faculty who teach no section, the same as the REST API" do
    create(:faculty, first_name: "Idle", last_name: "Person")

    expect(call(q: "idle").structured_content[:instructors]).to be_empty
  end

  it "treats LIKE wildcards as text" do
    teaching(first_name: "Grace", last_name: "Hopper")

    expect(call(q: "%").structured_content[:instructors]).to be_empty
  end

  it "counts a semantic search against the token's budget" do
    budget = instance_double(McpTools::SemanticBudget, spend!: nil)
    allow(McpTools::SemanticBudget).to receive(:new).and_return(budget)

    call(q: "robotics", semantic: true)

    expect(budget).to have_received(:spend!)
  end
end
