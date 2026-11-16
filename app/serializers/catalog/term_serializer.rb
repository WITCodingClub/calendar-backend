# frozen_string_literal: true

module Catalog
  # A term as the public catalog API returns it. section_count counts the
  # active sections.
  class TermSerializer
    def self.section_counts = Course.active.group(:term_id).count

    # One grouped count for the whole list, not one count per term.
    def self.collection(terms)
      counts = section_counts
      terms.map { |term| new(term, section_count: counts.fetch(term.id, 0)).as_json }
    end

    def self.with_section_count(term)
      new(term, section_count: Course.active.where(term_id: term.id).count).as_json
    end

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
