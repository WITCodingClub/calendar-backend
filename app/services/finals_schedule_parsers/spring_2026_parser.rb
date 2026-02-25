# frozen_string_literal: true

module FinalsScheduleParsers
  # Parser for the Spring 2026 finals schedule PDF format.
  #
  # pdftotext renders this wide 7-column table one column at a time per page,
  # with explicit named column headers on every page:
  #
  #   COURSE SECTION(S) COURSE TITLE  [course section + title pairs — ignored]
  #   CRN                             [one 5-digit CRN per line]
  #   INSTRUCTOR                      [instructor names — ignored]
  #   EXAM-DATE                       [date strings or ONLINE / SEE FACULTY]
  #   EXAM-TIME-OF-DAY                [time ranges, only for courses with exams]
  #   EXAM-ROOM                       [room codes, only for courses with exams]
  #
  # Key difference from Fall 2025: this format has an INSTRUCTOR column and no
  # COMBINED CRNs column. ONLINE / SEE FACULTY entries appear in the EXAM-DATE
  # column with blank time and room, so CRN count == date count (N) while time
  # and room counts are smaller (M ≤ N).
  #
  # Strategy: single-pass state machine across all pages, collecting each named
  # column into its own array. CRN and date arrays are zipped (same length N).
  # A separate index advances through times/rooms only when the date is real
  # (not ONLINE / SEE FACULTY / TBA), keeping the arrays correctly aligned.
  class Spring2026Parser < BaseParser
    SECTION_HEADERS = %w[CRN INSTRUCTOR EXAM-DATE EXAM-TIME-OF-DAY EXAM-ROOM].freeze

    def self.matches?(text)
      # Distinguishing markers vs Fall 2025: has INSTRUCTOR as a standalone
      # column header and EXAM-DATE header, but no COMBINED CRNs column.
      text.match?(/^INSTRUCTOR$/m) && text.match?(/^EXAM-DATE$/m)
    end

    def parse(text)
      lines     = preprocess_text(text).lines.map(&:strip).reject(&:empty?)
      state     = :none
      all_crns  = []
      all_dates = []
      all_times = []
      all_rooms = []

      lines.each do |line|
        case line
        when "CRN"              then state = :crn
        when "INSTRUCTOR"       then state = :none # skip — not needed for parsing
        when "EXAM-DATE"        then state = :exam_date
        when "EXAM-TIME-OF-DAY" then state = :exam_time
        when "EXAM-ROOM"        then state = :exam_room
        else
          case state
          when :crn
            all_crns << line.to_i if line.match?(/^\d{5}$/)

          when :exam_date
            # Collect real dates AND no-exam markers (ONLINE, SEE FACULTY, TBA)
            # so the dates array stays the same length as the CRNs array.
            all_dates << line if extract_date(line) || no_exam_entry?(line)

          when :exam_time
            st, et = extract_time_range(line)
            all_times << [st, et] if st

          when :exam_room
            # extract_location filters out cross-page noise (page footers, course
            # section codes, titles, etc.) while collecting valid room strings.
            loc = extract_location(line)
            all_rooms << loc if loc
          end
        end
      end

      build_entries(all_crns, all_dates, all_times, all_rooms)
    end

    private

    def build_entries(all_crns, all_dates, all_times, all_rooms)
      time_room_idx = 0
      entries       = []

      all_crns.zip(all_dates).each do |crn, date_line|
        next unless crn && crn >= 10_000
        next if date_line.nil?

        # ONLINE / SEE FACULTY / TBA — no scheduled exam, skip
        next if no_exam_entry?(date_line)

        date = extract_date(date_line)
        next unless date

        st, et   = all_times[time_room_idx] || [nil, nil]
        location = all_rooms[time_room_idx]
        time_room_idx += 1

        entries << {
          crn: crn,
          combined_crns: [crn],
          date: date,
          start_time: st,
          end_time: et,
          location: location
        }
      end

      # Keep only the first occurrence per CRN
      seen = {}
      entries.select { |e| seen[e[:crn]] ? false : (seen[e[:crn]] = true) }
    end

  end
end
