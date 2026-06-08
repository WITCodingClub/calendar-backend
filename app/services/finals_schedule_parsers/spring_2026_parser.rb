# frozen_string_literal: true

module FinalsScheduleParsers
  class Spring2026Parser < BaseParser
    SECTION_HEADERS = %w[CRN INSTRUCTOR EXAM-DATE EXAM-TIME-OF-DAY EXAM-ROOM].freeze

    def self.matches?(text)
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
        when "INSTRUCTOR"       then state = :none
        when "EXAM-DATE"        then state = :exam_date
        when "EXAM-TIME-OF-DAY" then state = :exam_time
        when "EXAM-ROOM"        then state = :exam_room
        else
          case state
          when :crn
            all_crns << line.to_i if line.match?(/^\d{5}$/)

          when :exam_date
            all_dates << line if extract_date(line) || no_exam_entry?(line)

          when :exam_time
            st, et = extract_time_range(line)
            all_times << [st, et] if st

          when :exam_room
            loc = extract_location(line)
            all_rooms << loc if loc && !no_exam_entry?(loc)
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
        next if no_exam_entry?(date_line)

        date = extract_date(date_line)
        next unless date

        st, et   = all_times[time_room_idx] || [nil, nil]
        location = all_rooms[time_room_idx]
        time_room_idx += 1

        entries << {
          crn:           crn,
          combined_crns: [crn],
          date:          date,
          start_time:    st,
          end_time:      et,
          location:      location
        }
      end

      seen = {}
      entries.select { |e| seen[e[:crn]] ? false : (seen[e[:crn]] = true) }
    end
  end
end
