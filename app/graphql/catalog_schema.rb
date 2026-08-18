# frozen_string_literal: true

# Public, read-only GraphQL schema for the WIT course catalog.
#
# There are no mutations and no user data. The limits below stop a single
# unauthenticated query from walking the whole catalog or nesting far enough to
# turn into a denial of service.
class CatalogSchema < GraphQL::Schema
  query Types::QueryType

  max_depth 12
  max_complexity 500
  default_page_size 50
  default_max_page_size 200

  # Filter errors are the client's fault, not a server bug, so surface the
  # message instead of a generic "Internal error".
  rescue_from(::Catalog::SectionQuery::FilterError) do |err|
    raise GraphQL::ExecutionError, err.message
  end

  def self.unauthorized_object(error)
    raise GraphQL::ExecutionError, "Not authorized to view #{error.type.graphql_name}"
  end
end
