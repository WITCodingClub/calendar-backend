# frozen_string_literal: true

module Types
  # The field class of every type in the catalog schema.
  #
  # graphql-ruby adds each field's complexity (1 by default) to the cost of a
  # query, scalar fields included. The IBM cost specification gives scalar and
  # enum fields a weight of 0 unless @cost says otherwise, so every field states
  # its weight. An analysis that reads the directives then gets the cost that
  # the server enforces, or a higher one.
  class BaseField < GraphQL::Schema::Field
    def initialize(*args, **kwargs, &block)
      super
      directive(Directives::Cost, weight: complexity.to_s) if complexity.is_a?(Numeric)
    end
  end
end
