# frozen_string_literal: true

module Catalog
  # Writes Banner's current seat, waitlist, and cross-list group counts for
  # every section of one term, and nothing else. Banner's class search gives
  # the counts for 500 sections in one request, so a term costs about four
  # requests.
  # Catalog::SectionSync sends three requests for each section, so the nightly
  # sync cannot keep seats current while students register.
  #
  # Catalog::SeatRefreshJob calls it for each term in its registration window.
  class SeatRefresh < ApplicationService
    COLUMNS = %i[seats_capacity seats_available waitlist_capacity waitlist_available
                 cross_list_capacity cross_list_available].freeze

    def initialize(term)
      @term = term
    end

    # Returns the number of sections whose counts changed, or nil when Banner
    # did not answer.
    def call
      fetched_at = Time.current
      result = LeopardWebClient.get_course_catalog(term: @term.uid)
      return nil unless result[:success]

      fresh = result[:courses].to_h { |section| [ section["courseReferenceNumber"].to_i, counts(section) ] }
      changed = @term.courses.pluck(:id, :crn, *COLUMNS).filter_map do |id, crn, *stored|
        next unless fresh.key?(crn)

        attrs = COLUMNS.zip(stored).to_h.merge(fresh[crn])
        [ id, attrs ] unless attrs.values == stored
      end

      now = Time.current
      written = Course.transaction do
        changed.sum do |id, attrs|
          # Only the count columns change, and no callback reads them. A row
          # that Catalog::SectionSync wrote during the fetch has newer counts
          # than this search, so it is left alone.
          Course.where(id: id, updated_at: ...fetched_at)
                .update_all(attrs.merge(updated_at: now)) # rubocop:disable Rails/SkipsModelValidations
        end
      end
      written
    end

    private

    # The same fields as Catalog::Importer. Each pair is written together or
    # not at all: the database checks that seats_available is not more than
    # seats_capacity, and half a count means nothing. An over-enrolled
    # section reports a negative number of seats, and it is kept.
    def counts(section)
      seats      = pair(section, "maximumEnrollment", "seatsAvailable", :seats_capacity, :seats_available)
      waitlist   = pair(section, "waitCapacity", "waitAvailable", :waitlist_capacity, :waitlist_available)
      cross_list = pair(section, "crossListCapacity", "crossListAvailable", :cross_list_capacity, :cross_list_available)
      seats.merge(waitlist, cross_list)
    end

    def pair(section, capacity_key, available_key, capacity_column, available_column)
      capacity, available = section.values_at(capacity_key, available_key)
      return {} if capacity.nil? || available.nil?

      { capacity_column => capacity.to_i, available_column => available.to_i }
    end
  end
end
