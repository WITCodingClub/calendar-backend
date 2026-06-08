# frozen_string_literal: true

module FinalsScheduleParsers
  class SpringFallParser < BaseParser
    def self.matches?(text)
      text.match?(/FINAL\s+(DAY|DATE)|MULTI-SECTION\s+CRNS/i)
    end

    def parse(text)
      normalized = preprocess_text(text)
      lines      = normalized.lines.map(&:strip).reject(&:empty?)
      records    = []
      i          = 0

      while i < lines.size
        line = lines[i]

        if line.match?(/^\d{5}$/)
          crn           = line.to_i
          combined_crns = [crn]
          j             = i + 1

          if j < lines.size && lines[j].match?(/^\d{5}(-\d{5})+$/)
            combined_crns = lines[j].split("-").map(&:to_i)
            j += 1
          end

          date       = nil
          start_time = nil
          end_time   = nil
          location   = nil
          date_found = false

          while j < lines.size
            break if lines[j].match?(/^\d{5}$/)

            if !date_found && (parsed = extract_date(lines[j]))
              date       = parsed
              date_found = true
              j += 1
              next
            end

            if date_found
              st, et = extract_time_range(lines[j])
              if st
                start_time = st
                end_time   = et
                if j + 1 < lines.size && !lines[j + 1].match?(/^\d{5}$/)
                  location = extract_location(lines[j + 1])
                end
                break
              end
            end

            j += 1
          end

          records << {
            crn:           crn,
            combined_crns: combined_crns,
            date:          date,
            start_time:    start_time,
            end_time:      end_time,
            location:      location
          }
        end

        i += 1
      end

      by_group = records
                 .select { |r| r[:date] }
                 .group_by { |r| r[:combined_crns].sort }

      records.each do |r|
        next if r[:date]

        donor = by_group[r[:combined_crns].sort]&.first
        next unless donor

        r[:date]       = donor[:date]
        r[:start_time] = donor[:start_time]
        r[:end_time]   = donor[:end_time]
        r[:location] ||= donor[:location]
      end

      records.select { |r| r[:date] && r[:start_time] && r[:end_time] }
    end
  end
end
