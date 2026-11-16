# frozen_string_literal: true

module Types
  # The GraphQL arguments of a catalog list, made from the filters that its
  # query object declares (Catalog::Filters), so the schema takes the same
  # filters as the REST API and the MCP tools.
  module CatalogFilterArguments
    module_function

    def define(owner, query)
      query.filters.each do |filter|
        options = { required: false, description: filter.description }
        options[:default_value] = false if filter.flag?
        owner.argument filter.name, type_of(filter), **options
      end
    end

    def type_of(filter)
      case filter.type
      when :integer               then Integer
      when :string, :time, :enum  then String
      when :flag, :strict_flag    then GraphQL::Types::Boolean
      when :strings               then [ String ]
      when :integers              then [ Integer ]
      when :days                  then [ DayOfWeekEnum ]
      when :schedule_types        then [ ScheduleTypeEnum ]
      end
    end
  end
end
