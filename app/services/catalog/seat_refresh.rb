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
    COLUMNS = BannerSection::COUNT_PAIRS.values.flatten.freeze

    def initialize(term)
      @term = term
    end

    # Returns the number of sections whose counts changed, or nil when Banner
    # did not answer.
    def call
      fetched_at = Time.current
      result = LeopardWebClient.get_course_catalog(term: @term.uid)
      return nil unless result[:success]

      fresh = result[:courses].to_h do |data|
        section = BannerSection.from_search(data)
        [ section.crn.to_i, section.counts ]
      end
      changed = @term.courses.pluck(:id, :crn, *COLUMNS).filter_map do |id, crn, *stored|
        next unless fresh.key?(crn)

        attrs = COLUMNS.zip(stored).to_h.merge(fresh[crn])
        [ id, attrs ] unless attrs.values == stored
      end

      now = Time.current
      Course.transaction do
        changed.sum do |id, attrs|
          # Only the count columns change, and no callback reads them. A row
          # that Catalog::SectionSync wrote during the fetch has newer counts
          # than this search, so it is left alone.
          Course.where(id: id, updated_at: ...fetched_at)
                .update_all(attrs.merge(updated_at: now)) # rubocop:disable Rails/SkipsModelValidations
        end
      end
    end
  end
end
