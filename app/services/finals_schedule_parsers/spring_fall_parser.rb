# frozen_string_literal: true

module FinalsScheduleParsers
  # Parser for Fall 2024, Spring 2025, and Summer 2025 finals schedule PDFs.
  #
  # pdftotext renders these as column-per-line: each field value is on its own
  # line, fields for successive rows are interleaved. We anchor on standalone
  # 5-digit CRN lines and scan forward for date → time → location.
  #
  # Spring 2025 / Fall 2024: each course has an individual CRN line followed
  # immediately by a combined-chain line ("27975-27976-..."); we use the chain
  # for combined_crns and consume both lines as one record.
  #
  # Summer 2025: each course has only an individual CRN (no chain).
  #
  # Fall 2024 backfill: some rows in a shared-CRN group omit date/time; after
  # building all records we fill in missing date/time from a sibling that has it.
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

          # Spring 2025 / Fall 2024: the next line is the combined CRN chain
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
            break if lines[j].match?(/^\d{5}$/) # next course CRN — stop

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
                # Location is the very next line after time (if not another CRN)
                if j + 1 < lines.size && !lines[j + 1].match?(/^\d{5}$/)
                  location = extract_location(lines[j + 1])
                end
                break
              end
            end

            j += 1
          end

          records << {
            crn: crn,
            combined_crns: combined_crns,
            date: date,
            start_time: start_time,
            end_time: end_time,
            location: location
          }
        end

        i += 1
      end

      # Backfill: fill in missing date/time from a sibling in the same combined
      # group. Handles Fall 2024 where only some rows carry date/time.
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
