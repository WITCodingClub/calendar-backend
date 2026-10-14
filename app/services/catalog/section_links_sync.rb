# frozen_string_literal: true

module Catalog
  # Stores Banner's lecture and lab pairs (fetchLinkedSections) for linked
  # sections. Our link identifiers do not always show the real pairs: in
  # Spring 2027, COMP 4960 lecture 20452 (A2) pairs with lab 20455 (B1).
  #
  #   Catalog::SectionLinksSync.call(course)  # one section
  #   Catalog::SectionLinksSync.for_term(term) # every linked section in a term
  #
  # A failed fetch keeps the old links and is reported. A section that is not
  # linked has no links, so it needs no request.
  class SectionLinksSync
    # Banner's search endpoints start to refuse after a burst of requests.
    PAUSE = 0.2

    def self.call(course)
      new(course).call
    end

    # @return [Hash] counts of synced and failed sections
    def self.for_term(term, pause: PAUSE)
      counts = { synced: 0, failed: 0 }

      term.courses.where(is_section_linked: true).find_each do |course|
        new(course).call ? counts[:synced] += 1 : counts[:failed] += 1
        sleep pause if pause.positive?
      end

      counts
    end

    def initialize(course)
      @course = course
    end

    # @return [Boolean] true when the links were stored
    def call
      return clear_links unless @course.is_section_linked

      groups = LeopardWebClient.fetch_linked_sections(term: @course.term.uid, course_reference_number: @course.crn)
      store(groups)
      true
    rescue LeopardWebClient::RequestError, LeopardWebClient::ParseError, Faraday::Error, JSON::ParserError => e
      Rails.error.report(e, handled: true, context: { course_id: @course.id, crn: @course.crn })
      false
    end

    private

    def store(groups)
      courses = Course.where(term_id: @course.term_id, crn: groups.flatten.pluck(:crn)).index_by(&:crn)
      now = Time.current

      rows = groups.each_with_index.flat_map do |group, index|
        group.filter_map do |entry|
          partner = courses[entry[:crn]]
          next if partner.nil? || partner.id == @course.id

          { course_id: @course.id, linked_course_id: partner.id, option_group: index,
            credit_hours: entry[:credit_hours], created_at: now, updated_at: now }
        end
      end

      SectionLink.transaction do
        SectionLink.where(course_id: @course.id).delete_all
        SectionLink.insert_all!(rows) if rows.any?
        @course.update_columns(links_fetched_at: now) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    # A section Banner no longer marks as linked has no partners.
    def clear_links
      SectionLink.where(course_id: @course.id).delete_all
      true
    end
  end
end
