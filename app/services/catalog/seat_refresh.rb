# frozen_string_literal: true

module Catalog
  # Writes Banner's current seat and waitlist counts for every section of one
  # term, and nothing else. Banner's class search gives the counts for 500
  # sections in one request, so a term costs about four requests.
  # Catalog::SectionSync sends three requests for each section, so the nightly
  # sync cannot keep seats current while students register.
  #
  # Catalog::SeatRefreshJob calls it for each term in its registration window.
  class SeatRefresh < ApplicationService
    COLUMNS = %i[seats_capacity seats_available waitlist_capacity waitlist_available].freeze

    def initialize(term)
      @term = term
    end

    # Returns the number of sections whose counts changed, or nil when Banner
    # did not answer.
    def call
      result = LeopardWebClient.get_course_catalog(term: @term.uid)
      return nil unless result[:success]

      fresh = result[:courses].to_h { |section| [ section["courseReferenceNumber"].to_i, counts(section) ] }
      changed = @term.courses.pluck(:id, :crn, *COLUMNS).filter_map do |id, crn, *stored|
        next unless fresh.key?(crn)

        attrs = COLUMNS.zip(stored).to_h.merge(fresh[crn])
        [ id, attrs ] unless attrs.values == stored
      end

      now = Time.current
      Course.transaction do
        changed.each do |id, attrs|
          # Only the count columns change, and no callback reads them.
          Course.where(id: id).update_all(attrs.merge(updated_at: now)) # rubocop:disable Rails/SkipsModelValidations
        end
      end
      changed.size
    end

    private

    # The same fields as Catalog::Importer. Each pair is written together or
    # not at all: the database checks that seats_available is not more than
    # seats_capacity, and half a waitlist means nothing. An over-enrolled
    # section reports a negative number of seats, and it is kept.
    def counts(section)
      seats    = pair(section, "maximumEnrollment", "seatsAvailable", :seats_capacity, :seats_available)
      waitlist = pair(section, "waitCapacity", "waitAvailable", :waitlist_capacity, :waitlist_available)
      seats.merge(waitlist)
    end

    def pair(section, capacity_key, available_key, capacity_column, available_column)
      capacity, available = section.values_at(capacity_key, available_key)
      return {} if capacity.nil? || available.nil?

      { capacity_column => capacity.to_i, available_column => available.to_i }
    end
  end
end
