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
      "list_programs"       => %i[degree_requirements],
      "degree_requirements" => %i[degree_requirements course_details],
      "list_term_electives" => %i[term_electives],
      "similar_sections"  => %i[sections],
      "check_schedule"    => %i[sections],
      "catalog_graphql"   => %i[sections course_details],
      "my_courses"        => %i[sections],
      "my_course_history" => %i[sections],
      "my_finals"         => %i[finals],
      "university_events" => %i[university_calendar]
    )
  end

  it "adds the advisory to the output schema of an academic planning tool, in either order" do
    schema = McpTools::Schemas.object(answer: McpTools::Schemas::INTEGER)
    before = Class.new(described_class) do
      academic_planning :sections
      output_schema schema
    end
    after = Class.new(described_class) do
      output_schema schema
      academic_planning :sections
    end

    [ before, after ].each do |tool|
      expect(tool.output_schema.to_h).to include(
        properties: { answer: { type: "integer" }, advisory: described_class::ADVISORY_SCHEMA },
        required:   %w[answer advisory]
      )
    end
    expect(tool_class(planning: false).tap { |tool| tool.output_schema(schema) }.output_schema.to_h[:properties].keys).to eq([ :answer ])
  end

  it "answers an unknown argument with a tool error that names the arguments" do
    result = tool_class(planning: false).call(server_context: mcp_context(user), instructor: "A Name")

    expect(result.error?).to be(true)
    expect(result.content.first[:text]).to eq("Unknown argument instructor. spec_tool takes no arguments.")
  end

  it "accepts every argument in the input schema of every tool" do
    McpTools.all.each do |tool|
      names = tool.input_schema_value.to_h.fetch(:properties, {}).keys.map(&:to_sym)
      params = tool.instance_method(:perform).parameters
      next if params.any? { |type, _| type == :keyrest }

      accepted = params.filter_map { |type, name| name if %i[key keyreq].include?(type) }
      expect(names - accepted).to be_empty, tool.name_value
    end
  end

  it "refuses an unknown data source" do
    expect { Class.new(described_class) { academic_planning :rumors } }.to raise_error(ArgumentError, /rumors/)
  end
end
