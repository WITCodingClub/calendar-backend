# frozen_string_literal: true

module Catalog
  # The filters of a catalog list, declared once on its query object. The
  # REST controllers read them from the request parameters
  # (Api::V1::PublicController), the GraphQL schema makes its arguments from
  # them (Types::CatalogFilterArguments), and the MCP tools make their input
  # schema from them (McpTools::CatalogFilters). A new filter is one line on
  # the query object.
  #
  #   extend Catalog::Filters
  #   filter :subject, :strings, "Subject codes, for example COMP or MATH."
  #
  # Types:
  # - :string, :integer, :time ("HH:MM"), :enum (one of values:)
  # - :strings, :integers, :days, :schedule_types (lists)
  # - :flag: any true value. :strict_flag: true or false only
  #   (Catalog::Params.strict_boolean).
  #
  # param: is the name in a REST request when it is not the filter name, and
  # mcp: the name of the MCP argument.
  module Filters
    LIST_TYPES = %i[strings integers days schedule_types].freeze
    TYPES = %i[string integer time enum flag strict_flag] + LIST_TYPES

    Filter = Data.define(:name, :type, :description, :param, :mcp, :values) do
      def list? = LIST_TYPES.include?(type)
      def flag? = %i[flag strict_flag].include?(type)
    end

    def filter(name, type, description, param: name, mcp: name, values: nil)
      raise ArgumentError, "unknown filter type #{type}" unless TYPES.include?(type)

      (@filters ||= []) << Filter.new(name:, type:, description:, param:, mcp:, values:)
    end

    def filters = @filters.dup

    def filter_names = @filters.map(&:name)

    # Raises FilterError for a filter the list does not have.
    def check_filters!(filters)
      unknown = filters.keys.map(&:to_sym) - filter_names
      raise FilterError, "Unknown filter(s): #{unknown.join(', ')}" if unknown.any?
    end
  end
end
