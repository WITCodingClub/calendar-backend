# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogSchema do
  let(:document) { GraphQL.parse(described_class.to_definition) }

  def directive_definition(name)
    document.definitions.find do |definition|
      definition.is_a?(GraphQL::Language::Nodes::DirectiveDefinition) && definition.name == name
    end
  end

  def arguments_of(definition)
    definition.arguments.map { |arg| [ arg.name, arg.type.to_query_string, arg.default_value ] }
  end

  def applied(member, directive_class)
    member.directives.find { |directive| directive.is_a?(directive_class) }&.arguments&.keyword_arguments
  end

  describe "the IBM GraphQL Cost Directives" do
    it "defines @cost as the specification does" do
      definition = directive_definition("cost")

      expect(arguments_of(definition)).to eq([ [ "weight", "String!", nil ] ])
      expect(definition.locations.map(&:name)).to contain_exactly(
        "ARGUMENT_DEFINITION", "ENUM", "FIELD_DEFINITION", "INPUT_FIELD_DEFINITION", "OBJECT", "SCALAR"
      )
    end

    it "defines @listSize as the specification does" do
      definition = directive_definition("listSize")

      expect(arguments_of(definition)).to contain_exactly(
        [ "assumedSize", "Int", nil ],
        [ "slicingArguments", "[String!]", nil ],
        [ "sizedFields", "[String!]", nil ],
        [ "requireOneSlicingArgument", "Boolean", true ]
      )
      expect(definition.locations.map(&:name)).to eq([ "FIELD_DEFINITION" ])
    end

    it "gives every field a weight equal to the complexity that the server counts" do
      described_class.types.each_value do |type|
        next if type.introspection? || !type.kind.fields?

        type.fields.each_value do |field|
          expect(applied(field, Directives::Cost)).to eq({ weight: field.complexity.to_s }),
                                                      "#{type.graphql_name}.#{field.graphql_name} has no matching @cost"
        end
      end
    end

    it "sizes each connection by first or last, and by the largest page without them" do
      %w[sections instructors reviews].each do |name|
        expect(applied(described_class.query.fields.fetch(name), Directives::ListSize)).to eq(
          slicing_arguments:            %w[first last],
          sized_fields:                 %w[edges nodes],
          assumed_size:                 described_class.default_max_page_size,
          require_one_slicing_argument: false
        )
      end
    end
  end

  describe "a cost analysis that reads only the directives" do
    # The analysis a client or a gateway runs from the SDL. Without @cost, a
    # scalar or enum field weighs 0 and any other field 1. A list with no
    # @listSize counts as one item, the smallest size it can assume.
    def static_cost(selections, owner, sizes = {})
      selections.sum do |node|
        field = described_class.get_field(owner, node.name)
        next 0.0 if field.nil?

        list_size = applied(field, Directives::ListSize)
        slice     = list_size && slicing_value(node, list_size)
        sized     = list_size&.dig(:sized_fields).presence
        count     = sized ? 1 : (slice || sizes.fetch(node.name, 1))
        children  = static_cost(node.selections, field.type.unwrap, sized ? sized.index_with(slice) : {})

        count * (weight(field) + children)
      end
    end

    def slicing_value(node, list_size)
      given = node.arguments.select { |arg| list_size[:slicing_arguments].to_a.include?(arg.name) }
      given.map(&:value).max || list_size[:assumed_size]
    end

    def weight(field)
      cost = applied(field, Directives::Cost)
      return cost[:weight].to_f if cost

      field.type.unwrap.kind.composite? ? 1.0 : 0.0
    end

    def costs(query_string)
      query  = GraphQL::Query.new(described_class, query_string)
      server = GraphQL::Analysis.analyze_query(query, [ GraphQL::Analysis::QueryComplexity ]).first
      static = static_cost(GraphQL.parse(query_string).definitions.first.selections, described_class.query)

      [ static, server ]
    end

    it "gets exactly the server's cost for a query with no connection" do
      static, server = costs("{ terms { uid name } section(crn: 1) { title term { name } linked { crns } } }")

      expect(static).to eq(server)
    end

    [
      "{ sections(first: 20) { totalCount pageInfo { hasNextPage endCursor } nodes { crn title " \
      "instructors { name rmp { avgRating } } meetingTimes { day location { display rooms { number } } } } } }",
      "{ instructors { edges { cursor node { name } } nodes { pubId } pageInfo { startCursor } } }",
      "{ sections(last: 5) { totalCount pageInfo { hasNextPage hasPreviousPage startCursor endCursor } } }",
      "{ sections(first: 1000) { nodes { crn } } }",
      "{ __typename terms { __typename uid } }"
    ].each do |query_string|
      it "never gets less than the server's cost for #{query_string[0, 40]}..." do
        static, server = costs(query_string)

        expect(static).to be >= server
      end
    end
  end

  it "counts __typename as 0, the weight that the specification gives a scalar field" do
    typename = described_class.introspection_system.dynamic_field(name: "__typename")

    expect(typename.complexity).to eq(0)
  end

  describe "limit directives" do
    it "publishes the query limits that the schema enforces" do
      expect(applied(described_class, Directives::QueryLimits)).to be_nil
      limits = described_class.schema_directives.find { |d| d.is_a?(Directives::QueryLimits) }.arguments.keyword_arguments

      expect(limits).to eq(
        max_cost:          described_class.max_complexity,
        max_depth:         described_class.max_depth,
        default_page_size: described_class.default_page_size,
        max_page_size:     described_class.default_max_page_size
      )
    end

    it "publishes the rate limit of the throttle that covers /api/graphql" do
      throttle = Rack::Attack.throttles.fetch("catalog/ip")
      request  = Rack::Attack::Request.new(Rack::MockRequest.env_for("/api/graphql", method: "POST"))
      limit    = described_class.schema_directives.find { |d| d.is_a?(Directives::RateLimit) }.arguments.keyword_arguments

      expect(Rack::Attack::PUBLIC_CATALOG_PATH.call(request)).to be(true)
      expect(limit).to eq(max: throttle.limit, window: throttle.period.to_i)
    end

    # The root types have their default names, so the SDL must declare the
    # directives with "extend schema", not with a schema definition.
    it "prints both limits on the schema" do
      schema = document.definitions.find { |definition| definition.is_a?(GraphQL::Language::Nodes::SchemaExtension) }

      expect(schema.directives.map(&:name)).to contain_exactly("queryLimits", "rateLimit")
    end
  end
end
