# frozen_string_literal: true

module FinalsScheduleParsers
  class Fall2025Parser < BaseParser
    def self.matches?(text)
      text.match?(/COMBINED\s+CRNs/i)
    end

    def parse(text)
      normalized = preprocess_text(text)
      lines      = normalized
                   .lines
                   .map(&:strip)
                   .reject { |l| l.empty? || header_line?(l) }

      classified      = lines.map { |l| { line: l, type: classify_line(l) } }
      crn_blocks      = extract_typed_blocks(classified, :crn)
      date_blocks     = extract_typed_blocks(classified, :date)
      time_blocks     = extract_typed_blocks(classified, :time)
      location_blocks = extract_typed_blocks(classified, :location)

      entries = []

      date_blocks.each do |date_block|
        n = date_block[:data].size

        crn_block = crn_blocks
                    .select { |b| b[:end_idx] < date_block[:start_idx] && b[:data].size == n }
                    .last
        next unless crn_block

        time_block = time_blocks
                     .select { |b| b[:start_idx] > date_block[:start_idx] && b[:data].size == n }
                     .first
        next unless time_block

        location_block = location_blocks
                         .select { |b| b[:start_idx] > time_block[:start_idx] && b[:data].size == n }
                         .first

        n.times do |i|
          crns     = crn_block[:data][i]
          date     = date_block[:data][i]
          st, et   = time_block[:data][i]
          location = location_block&.dig(:data, i)

          next unless date && st && et
          next if crns.empty?

          crns.each do |crn|
            entries << {
              crn:           crn,
              combined_crns: crns,
              date:          date,
              start_time:    st,
              end_time:      et,
              location:      location
            }
          end
        end
      end

      seen = {}
      entries.select { |e| seen[e[:crn]] ? false : (seen[e[:crn]] = true) }
    end

    private

    def classify_line(line)
      return :crn      if crn_only_line?(line)
      return :date     if date_only_line?(line)
      return :time     if time_only_line?(line)
      return :location if location_only_line?(line)

      :other
    end

    def crn_only_line?(line)
      normalize_merged_crns(line).match?(/^\d{5}(-\d{5})*$/)
    end

    def date_only_line?(line)
      line.match?(/^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),/i)
    end

    def time_only_line?(line)
      st, _et = extract_time_range(line)
      return false unless st
      return false if date_only_line?(line)
      return false if line.match?(/[A-Z]{4,6}\s+\S/)

      true
    end

    def location_only_line?(line)
      return true if line.match?(/^[A-Z]{4,6}\s+[\dA-Z]{3,}(?:\/[\dA-Z]+)*\s*$/i)
      return true if line.match?(/^[A-Z][A-Za-z]+\s+(?:Auditorium|Hall|Center|Room)\s*$/i)
      return true if line.match?(/^(ONLINE|TBA|VIRTUAL|SEE FACULTY)/i)

      false
    end

    def extract_typed_blocks(classified_lines, type)
      blocks        = []
      current_block = nil

      classified_lines.each_with_index do |item, idx|
        if item[:type] == type
          current_block ||= { start_idx: idx, end_idx: idx, data: [] }
          current_block[:end_idx] = idx

          data = case type
                 when :crn      then parse_crn_line(item[:line])
                 when :date     then extract_date(item[:line])
                 when :time     then extract_time_range(item[:line])
                 when :location then extract_location(item[:line])
                 end
          current_block[:data] << data
        else
          blocks << current_block if current_block
          current_block = nil
        end
      end

      blocks << current_block if current_block
      blocks
    end

    def parse_crn_line(line)
      normalize_merged_crns(line)
        .scan(/\d{5}(?:-\d{5})*/)
        .flat_map { |m| m.split("-").map(&:to_i) }
        .select { |n| n >= 10_000 }
        .uniq
    end

    def normalize_merged_crns(line)
      line.gsub(/(\d{5})(\d{5})/, '\1-\2')
    end

    def header_line?(line)
      line.match?(/COURSE SECTION|COMBINED CRNs|EXAM-DATE|EXAM-TIME|EXAM-ROOM|FALL \d{4} FINAL|Page \d+/i)
    end
  end
end
