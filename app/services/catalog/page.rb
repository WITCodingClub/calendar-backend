# frozen_string_literal: true

module Catalog
  # One page of a catalog list. The REST API, the GraphQL schema, and the MCP
  # tools read the page sizes of each list from SIZES, so the three surfaces
  # page alike. docs/public-catalog-api.md gives the same numbers.
  class Page
    SIZES = {
      sections:    { default: 50, max: 200 },
      instructors: { default: 50, max: 200 },
      courses:     { default: 25, max: 100 },
      reviews:     { default: 25, max: 100 }
    }.freeze

    def self.default_size(list) = SIZES.fetch(list)[:default]
    def self.max_size(list)     = SIZES.fetch(list)[:max]

    attr_reader :number, :per_page

    # page and per_page come from the caller: a string, an integer, or nil. A
    # page below 1 is page 1, and per_page is clamped to the list's maximum,
    # so one request cannot pull the whole catalog.
    def initialize(list, page: nil, per_page: nil)
      @number   = [ page.to_i, 1 ].max
      @per_page = (per_page.presence&.to_i || self.class.default_size(list)).clamp(1, self.class.max_size(list))
    end

    def of(relation)
      relation.page(number).per(per_page)
    end

    def meta(total_count)
      { page: number, per_page: per_page, total_count: total_count, total_pages: (total_count.to_f / per_page).ceil }
    end
  end
end
