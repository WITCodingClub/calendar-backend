# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::ListRequest do
  let(:term) { create(:term) }

  it "gives a page of rows and its meta" do
    create_list(:course, 3, term: term)

    list = described_class.new(:sections, { term_uid: term.uid }, per_page: 2)

    expect(list.rows.size).to eq(2)
    expect(list.meta).to eq(page: 1, per_page: 2, total_count: 3, total_pages: 2)
  end

  it "adds the review source to the meta of reviews" do
    expect(described_class.new(:reviews, {}).meta).to include(source: Catalog::ReviewSerializer::SOURCE)
  end

  it "uses the smaller MCP page sizes for an MCP tool" do
    list = described_class.new(:instructors, {}, per_page: 500, surface: :mcp)

    expect(list.page.per_page).to eq(Catalog::Page.max_size(:instructors, surface: :mcp))
  end

  # A filter declared on the query object reaches every surface.
  describe "declared filters" do
    {
      sections:    [ McpTools::SearchSections, ->(schema) { Types::SectionFilterInput.arguments } ],
      courses:     [ McpTools::SearchCourses, ->(schema) { schema.query.fields["courses"].arguments } ],
      instructors: [ McpTools::SearchInstructors, ->(schema) { schema.query.fields["instructors"].arguments } ],
      reviews:     [ McpTools::SearchReviews, ->(schema) { schema.query.fields["reviews"].arguments } ]
    }.each do |list, (tool, graphql_arguments)|
      it "gives the #{list} filters to the MCP tool and the GraphQL schema" do
        filters = described_class.query(list).filters

        expect(tool.input_schema_value.to_h[:properties].keys).to include(*filters.map(&:mcp))
        connection_arguments = %w[first last before after]
        expect(graphql_arguments.call(CatalogSchema).keys - connection_arguments)
          .to match_array(filters.map { |f| f.name.to_s.camelize(:lower) })
      end
    end
  end
end
