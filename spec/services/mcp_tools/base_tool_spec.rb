# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::BaseTool do
  let(:user) { create(:user) }

  def tool_class(planning:)
    Class.new(described_class) do
      tool_name "spec_tool"
      requires_scope "catalog"
      academic_planning :sections if planning

      def perform = { answer: 1 }
    end
  end

  it "adds the advisory and the data sources to the result of an academic planning tool" do
    result = tool_class(planning: true).call(server_context: mcp_context(user))

    expect(result.structured_content).to eq(
      answer:   1,
      advisory: { message: described_class::ADVISORY, data_sources: Catalog::Freshness.call([ :sections ]) }
    )
    expect(JSON.parse(result.content.first[:text]).dig("advisory", "message")).to eq(described_class::ADVISORY)
  end

  it "leaves the advisory out of other tools" do
    result = tool_class(planning: false).call(server_context: mcp_context(user))

    expect(result.structured_content).to eq(answer: 1)
  end

  it "names the data sources of each academic planning tool" do
    planning = McpTools.all.select(&:academic_planning?).to_h { |tool| [ tool.name_value, tool.data_sources ] }

    expect(planning).to eq(
      "search_sections"   => %i[sections],
      "get_section"       => %i[sections],
      "search_courses"    => %i[course_details],
      "get_course"        => %i[course_details sections],
      "similar_sections"  => %i[sections],
      "check_schedule"    => %i[sections],
      "catalog_graphql"   => %i[sections course_details],
      "my_courses"        => %i[sections],
      "my_course_history" => %i[sections],
      "my_finals"         => %i[finals],
      "university_events" => %i[university_calendar]
    )
  end

  it "refuses an unknown data source" do
    expect { Class.new(described_class) { academic_planning :rumors } }.to raise_error(ArgumentError, /rumors/)
  end
end
