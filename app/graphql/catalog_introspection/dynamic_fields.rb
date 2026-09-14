# frozen_string_literal: true

module CatalogIntrospection
  # __typename with a complexity of 0. graphql-ruby counts it as 1, but the IBM
  # cost specification weighs a scalar field at 0, and clients such as Apollo
  # add __typename to every selection. Without this, a cost analysis that reads
  # the schema directives would get less than the server's cost.
  class DynamicFields < GraphQL::Introspection::DynamicFields
    field :__typename, String, "The name of this type",
          null: false, dynamic_introspection: true, resolve_each: true, complexity: 0
  end
end
