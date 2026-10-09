# frozen_string_literal: true

module FinalsSchedules
  module Parsers
    # pdftotext prints this template one column at a time: every CRN on the
    # page, then every exam date, then every time, then every room. The parser
    # pairs the columns by position, one page (one set of headers) at a time.
    #
    # The time and room columns have a value only for rows with a dated exam,
    # or a value for every row. When a column has any other count, a row did
    # not parse, and pairing by position would give later rows the wrong
    # values. A bad date or time column skips the page. A bad room column
    # keeps the exams with no location. Both add a warning.
    class Spring2026Parser < BaseParser
      SECTION_HEADERS = %w[CRN INSTRUCTOR EXAM-DATE EXAM-TIME-OF-DAY EXAM-ROOM].freeze

      def self.matches?(text)
        text.match?(/^CRN$/m) && text.match?(/^EXAM-TIME-OF-DAY$/m) && !text.match?(/COMBINED\s+CRNs/i)
      end

      def parse(text)
        @warnings = []
        lines   = preprocess_text(text).lines.map(&:strip).reject(&:empty?)
        state   = :none
        pages   = []
        current = nil

        lines.each do |line|
          case line
          when "CRN"
            current = new_page
            pages << current
            state = :crn
          when "INSTRUCTOR"       then state = :none
          when "EXAM-DATE"        then state = :exam_date
          when "EXAM-TIME-OF-DAY" then state = :exam_time
          when "EXAM-ROOM"        then state = :exam_room
          else
            next unless current

            case state
            when :crn
              current[:crns] << line.to_i if line.match?(/^\d{5}$/)

            when :exam_date
              current[:dates] << line if extract_date(line) || no_exam_entry?(line)

            when :exam_time
              st, et = extract_time_range(line)
              current[:times] << [ st, et ] if st

            when :exam_room
              loc = extract_location(line)
              current[:rooms] << loc if loc
            end
          end
        end

        entries = pages.each_with_index.flat_map { |page, index| build_entries(page, index + 1) }

        seen = {}
        entries.select { |e| seen[e[:crn]] ? false : (seen[e[:crn]] = true) }
      end

      private

      def new_page
        { crns: [], dates: [], times: [], rooms: [] }
      end

      def build_entries(page, page_number)
        crns  = page[:crns]
        dates = page[:dates]

        if dates.size != crns.size
          return skip_page(page_number, "#{crns.size} CRNs but #{dates.size} exam dates")
        end

        dated_rows = crns.each_index.select { |i| !no_exam_entry?(dates[i]) && extract_date(dates[i]) }
        times      = align(page[:times], crns.size, dated_rows)
        rooms      = align(page[:rooms], crns.size, dated_rows)

        return skip_page(page_number, "#{dated_rows.size} dated exams but #{page[:times].size} exam times") unless times

        unless rooms
          warn_page(page_number, "#{dated_rows.size} dated exams but #{page[:rooms].size} exam rooms; locations left blank")
          rooms = {}
        end

        dated_rows.filter_map do |i|
          crn = crns[i]
          next unless crn >= 10_000

          st, et   = times[i]
          location = rooms[i]

          {
            crn:           crn,
            combined_crns: [ crn ],
            date:          extract_date(dates[i]),
            start_time:    st,
            end_time:      et,
            location:      no_exam_entry?(location.to_s) ? nil : location
          }
        end
      end

      # Maps a time or room column to row indexes. Returns nil when the column
      # length matches neither every row nor the dated rows only.
      def align(values, row_count, dated_rows)
        if values.size == row_count
          values.each_with_index.to_h { |value, i| [ i, value ] }
        elsif values.size == dated_rows.size
          dated_rows.zip(values).to_h
        end
      end

      def skip_page(page_number, reason)
        warn_page(page_number, "#{reason}; page skipped")
        []
      end

      def warn_page(page_number, reason)
        message = "Spring 2026 finals page #{page_number}: #{reason}"
        Rails.logger.warn(message)
        warnings << message
      end
    end
  end
end
