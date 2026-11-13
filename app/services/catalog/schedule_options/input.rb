# frozen_string_literal: true

module Catalog
  module ScheduleOptions
    # Reads and checks the body of POST /api/v1/catalog/schedule_options (and
    # /count) and the arguments of the find_schedules MCP tool. A bad value
    # raises Catalog::FilterError, which the API turns into 400
    # INVALID_FILTER.
    #
    # The limits bound the work of one public, uncached request.
    class Input
      MAX_COURSES          = 10
      MAX_CODES_PER_COURSE = 5
      MAX_CODES            = 20
      MAX_CRNS             = ScheduleCheck::MAX_CRNS
      DEFAULT_LIMIT        = 6
      MAX_LIMIT            = 20

      COURSE_KEYS = %w[codes crns].freeze

      # One course entry: one code, or "one of" several codes. Each code is
      # [subject_code, course_number]. crns pins sections of the entry.
      Entry = Data.define(:index, :codes, :crns)

      attr_reader :term_uid, :entries, :preferences, :limit

      # @param params [Hash, ActionController::Parameters] term_uid, courses,
      #   preferences, limit. Other keys are ignored, the same as an unknown
      #   query parameter on the GET routes.
      def initialize(params)
        params       = normalize(params)
        @term_uid    = parse_term_uid(params["term_uid"])
        @entries     = parse_courses(params["courses"])
        @preferences = Preferences.parse(params["preferences"])
        @limit       = parse_limit(params["limit"])
      end

      def pinned_crns = entries.flat_map(&:crns)

      private

      def normalize(params)
        hash = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
        hash.deep_stringify_keys
      end

      def parse_term_uid(value)
        uid = integer(value)
        raise FilterError, "Give term_uid, a term code such as 202720" if uid.nil?

        uid
      end

      def parse_courses(value)
        unless value.is_a?(Array) && value.any?
          raise FilterError, "Give courses, a list of course entries such as { \"codes\": [\"COMP 3350\"] }"
        end
        raise FilterError, "Give at most #{MAX_COURSES} courses" if value.size > MAX_COURSES

        entries = value.each_with_index.map { |entry, index| parse_entry(entry, index) }
        twice = entries.group_by { |entry| entry.codes.sort }.find { |_codes, list| list.size > 1 }
        raise FilterError, "#{twice.first.map { |code| code.join(' ') }.join(' or ')} is in two course entries" if twice
        raise FilterError, "Give at most #{MAX_CODES} course codes in all" if entries.sum { |entry| entry.codes.size } > MAX_CODES
        raise FilterError, "Give at most #{MAX_CRNS} CRNs in all" if entries.sum { |entry| entry.crns.size } > MAX_CRNS

        entries
      end

      def parse_entry(entry, index)
        raise FilterError, "Each course must be an object with codes" unless entry.is_a?(Hash)

        unknown = entry.keys - COURSE_KEYS
        raise FilterError, "Unknown course key(s): #{unknown.join(', ')}" if unknown.any?

        Entry.new(index: index, codes: parse_codes(entry["codes"]), crns: parse_crns(entry["crns"]))
      end

      def parse_codes(value)
        codes = value.is_a?(String) ? [ value ] : value
        raise FilterError, "Each course needs codes, a list of course codes" unless codes.is_a?(Array) && codes.any?
        if codes.size > MAX_CODES_PER_COURSE
          raise FilterError, "Give at most #{MAX_CODES_PER_COURSE} codes in one course"
        end

        codes.map do |code|
          CatalogCourse.parse_code(code.to_s) ||
            raise(FilterError, "Unknown course #{code.inspect}; use a code such as COMP 3350")
        end.uniq
      end

      def parse_crns(value)
        return [] if value.nil?
        raise FilterError, "crns must be a list of CRNs" unless value.is_a?(Array)

        value.map { |crn| integer(crn) || raise(FilterError, "Invalid CRN #{crn.inspect}") }.uniq
      end

      def parse_limit(value)
        return DEFAULT_LIMIT if value.nil?

        limit = integer(value)
        raise FilterError, "limit must be a number from 1 to #{MAX_LIMIT}" if limit.nil?

        limit.clamp(1, MAX_LIMIT)
      end

      def integer(value)
        case value
        when Integer then value
        when /\A\s*\d+\s*\z/ then value.to_i
        end
      end
    end
  end
end
