# frozen_string_literal: true

# Public, read-only GraphQL schema for the WIT course catalog.
#
# There are no mutations and no user data. The limits below stop a single
# unauthenticated query from walking the whole catalog or nesting far enough to
# turn into a denial of service.
class CatalogSchema < GraphQL::Schema
  query Types::QueryType
  introspection CatalogIntrospection

  max_depth 12
  max_complexity 500
  default_page_size 50
  default_max_page_size 200

  directives Directives::Cost, Directives::ListSize, Directives::QueryLimits, Directives::RateLimit

  # Machine-readable copies of the limits above, and of the Rack::Attack
  # throttle that covers /api/graphql. They read the real values, so the schema
  # cannot publish a limit that the server does not enforce.
  schema_directive Directives::QueryLimits,
                   max_cost:          max_complexity,
                   max_depth:         max_depth,
                   default_page_size: default_page_size,
                   max_page_size:     default_max_page_size

  schema_directive Directives::RateLimit,
                   max:    Rack::Attack.throttles.fetch("catalog/ip").limit,
                   window: Rack::Attack.throttles.fetch("catalog/ip").period.to_i

  # Filter errors are the client's fault, not a server bug, so surface the
  # message instead of a generic "Internal error".
  rescue_from(::Catalog::FilterError) do |err|
    raise GraphQL::ExecutionError, err.message
  end

  def self.unauthorized_object(error)
    raise GraphQL::ExecutionError, "Not authorized to view #{error.type.graphql_name}"
  end
end
