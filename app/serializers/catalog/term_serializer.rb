# frozen_string_literal: true

module Catalog
  # A term as the public catalog API returns it.
  class TermSerializer
    def initialize(term, section_count: nil)
      @term          = term
      @section_count = section_count
    end

    def as_json(*)
      return nil if @term.nil?

      {
        uid:           @term.uid,
        name:          @term.name,
        season:        @term.season,
        year:          @term.year,
        start_date:    @term.start_date,
        end_date:      @term.end_date,
        section_count: @section_count
      }.compact
    end
  end
end
