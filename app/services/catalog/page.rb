# frozen_string_literal: true

module Catalog
  # One page of a catalog list. Every surface reads its page sizes here.
  # SIZES are the sizes of the REST API, GRAPHQL_SIZES of the GraphQL schema
  # (docs/public-catalog-api.md gives the same numbers). MCP_SIZES are
  # smaller on purpose: a tool result goes into a model's context, so each
  # row costs tokens (docs/mcp.md).
  class Page
    SIZES = {
      sections:    { default: 50, max: 200 },
      instructors: { default: 50, max: 200 },
      courses:     { default: 25, max: 100 },
      reviews:     { default: 25, max: 100 }
    }.freeze

    MCP_SIZES = {
      sections:    { default: 20, max: 100 },
      instructors: { default: 10, max: 50 },
      courses:     { default: 25, max: 100 },
      reviews:     { default: 25, max: 50 }
    }.freeze

    # Every GraphQL connection allows 200, and a page is 50 without first or
    # last (CatalogSchema). Third-party clients rely on this public limit.
    GRAPHQL_SIZES = SIZES.transform_values { { default: 50, max: 200 } }.freeze

    SURFACES = { api: SIZES, graphql: GRAPHQL_SIZES, mcp: MCP_SIZES }.freeze

    def self.default_size(list, surface: :api) = SURFACES.fetch(surface).fetch(list)[:default]
    def self.max_size(list, surface: :api)     = SURFACES.fetch(surface).fetch(list)[:max]

    attr_reader :number, :per_page

    # page and per_page come from the caller: a string, an integer, or nil. A
    # page below 1 is page 1, and per_page is clamped to the list's maximum,
    # so one request cannot pull the whole catalog.
    def initialize(list, page: nil, per_page: nil, surface: :api)
      @number   = [ page.to_i, 1 ].max
      @per_page = (per_page.presence&.to_i || self.class.default_size(list, surface: surface))
                  .clamp(1, self.class.max_size(list, surface: surface))
    end

    def of(relation)
      relation.page(number).per(per_page)
    end

    def meta(total_count)
      { page: number, per_page: per_page, total_count: total_count, total_pages: (total_count.to_f / per_page).ceil }
    end
  end
end
