# frozen_string_literal: true

module Directives
  # The @listSize directive from the IBM GraphQL Cost Directives specification:
  # https://ibm.github.io/graphql-specs/cost-spec.html#sec-The-List-Size-Directive
  class ListSize < GraphQL::Schema::Directive
    graphql_name "listSize"
    description "The size of the list that a field returns, as defined by the IBM GraphQL Cost " \
                "Directives specification."

    locations FIELD_DEFINITION

    argument :assumed_size, Integer, required: false,
             description: "The maximum length of the list."
    argument :slicing_arguments, [ String ], required: false,
             description: "The arguments whose value sets the length of the list."
    argument :sized_fields, [ String ], required: false,
             description: "The subfields whose list length the size sets, instead of this field."
    argument :require_one_slicing_argument, Boolean, required: false, default_value: true,
             description: "Whether a query must give exactly one of the slicing arguments."
  end
end
