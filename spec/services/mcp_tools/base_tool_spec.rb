# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::BaseTool do
  let(:user) { create(:user) }

  def tool_class(planning:)
    Class.new(described_class) do
      tool_name "spec_tool"
      requires_scope "catalog"
      academic_planning if planning

      def perform = { answer: 1 }
    end
  end

  it "adds the advisory and the data sources to the result of an academic planning tool" do
    result = tool_class(planning: true).call(server_context: mcp_context(user))

    expect(result.structured_content).to eq(
      answer:   1,
      advisory: { message: described_class::ADVISORY, data_sources: Catalog::Freshness.call }
    )
    expect(JSON.parse(result.content.first[:text]).dig("advisory", "message")).to eq(described_class::ADVISORY)
  end

  it "leaves the advisory out of other tools" do
    result = tool_class(planning: false).call(server_context: mcp_context(user))

    expect(result.structured_content).to eq(answer: 1)
  end

  it "marks the course and schedule tools as academic planning" do
    planning = McpTools.all.select(&:academic_planning?).map(&:name_value)

    expect(planning).to match_array(%w[
      search_sections get_section search_courses get_course similar_sections check_schedule
      catalog_graphql my_courses my_course_history
    ])
  end
end
