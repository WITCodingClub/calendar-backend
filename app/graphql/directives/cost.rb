# frozen_string_literal: true

module Directives
  # The @cost directive from the IBM GraphQL Cost Directives specification:
  # https://ibm.github.io/graphql-specs/cost-spec.html#sec-The-Cost-Directive
  class Cost < GraphQL::Schema::Directive
    graphql_name "cost"
    description "The weight that this schema member adds to the cost of a query, as defined by " \
                "the IBM GraphQL Cost Directives specification."

    locations ARGUMENT_DEFINITION, ENUM, FIELD_DEFINITION, INPUT_FIELD_DEFINITION, OBJECT, SCALAR

    argument :weight, String, required: true,
             description: "The cost that each appearance adds, as a serialized Float."
  end
end
