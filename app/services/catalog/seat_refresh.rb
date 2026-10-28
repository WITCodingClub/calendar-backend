# frozen_string_literal: true

module Catalog
  # Writes Banner's current seat counts for every section of one term, and
  # nothing else. Banner's class search gives the counts for 500 sections in
  # one request, so a term costs about four requests. Catalog::SectionSync
  # sends three requests for each section, so the nightly sync cannot keep
  # seats current while students register.
  #
  # Catalog::SeatRefreshJob calls it for each term in its registration window.
  class SeatRefresh < ApplicationService
    def initialize(term)
      @term = term
    end

    # Returns the number of sections whose counts changed, or nil when Banner
    # did not answer.
    def call
      result = LeopardWebClient.get_course_catalog(term: @term.uid)
      return nil unless result[:success]

      fresh = result[:courses].to_h { |section| [ section["courseReferenceNumber"].to_i, seat_counts(section) ] }
      changed = @term.courses.pluck(:id, :crn, :seats_capacity, :seats_available).filter_map do |id, crn, capacity, available|
        counts = fresh[crn]
        # Set both counts together or neither. The database checks that
        # seats_available is not more than seats_capacity.
        next if counts.nil? || counts.any?(&:nil?)
        next if counts == [ capacity, available ]

        [ id, counts ]
      end

      now = Time.current
      Course.transaction do
        changed.each do |id, (capacity, available)|
          # Only the seat columns change, and no callback reads them.
          Course.where(id: id).update_all(seats_capacity: capacity, seats_available: available, updated_at: now) # rubocop:disable Rails/SkipsModelValidations
        end
      end
      changed.size
    end

    private

    # The same fields as Catalog::Importer#seat_counts. An over-enrolled section
    # reports a negative number of seats, and it is kept.
    def seat_counts(section)
      [ section["maximumEnrollment"], section["seatsAvailable"] ].map { |value| value&.to_i }
    end
  end
end
