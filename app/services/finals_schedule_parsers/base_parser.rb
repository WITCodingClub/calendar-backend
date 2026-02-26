# frozen_string_literal: true

module FinalsScheduleParsers
  # Abstract base class for all WIT finals schedule PDF parsers.
  #
  # Subclasses must implement:
  #   self.matches?(text) → true when this parser handles the given PDF text
  #   parse(text)         → array of exam entry hashes
  #
  # Each entry hash:
  #   { crn:, combined_crns:, date:, start_time:, end_time:, location: }
  #
  # Shared helpers (extract_date, extract_time_range, extract_location, etc.)
  # are defined here and available to all subclasses.
  class BaseParser
    # Returns true if this parser can handle the given PDF text.
    def self.matches?(_text)
      raise NotImplementedError, "#{name}.matches? must be implemented"
    end

    # Parses PDF text and returns an array of exam entry hashes.
    def parse(_text)
      raise NotImplementedError, "#{self.class}#parse must be implemented"
    end

    private

    # Strip common PDF artefacts that trip up parsers.
    def preprocess_text(text)
      text
        .gsub(/^\*\s+/, "")                                # "* ARCH1500..." → "ARCH1500..."
        .gsub(/Date & Time Change\s*$/i, "")               # amendment annotation column
        .gsub(/FINAL SCHEDULE INFORMATION.*$/i, "")        # info column header/content
        .gsub(/Schedule as of [\d\/]+\s*$/i, "")           # footer datestamp
        .gsub(/UPDATED\s+(?=FALL|SPRING|SUMMER)/i, "") # "UPDATED FALL 2025" → "FALL 2025"
    end

    def extract_date(line)
      # MM/DD/YYYY
      if line =~ /(\d{1,2})\/(\d{1,2})\/(\d{4})/
        return Date.new($3.to_i, $1.to_i, $2.to_i)
      end

      # "December 8, 2025" / "December 8 2025"
      if line =~ %r{(January|February|March|April|May|June|July|August|
                   September|October|November|December)\s+(\d{1,2}),?\s+(\d{4})}xi
        month = Date::MONTHNAMES.index($1.capitalize)
        return Date.new($3.to_i, month, $2.to_i)
      end

      # "Dec 8, 2025"
      if line =~ /(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{1,2}),?\s+(\d{4})/i
        month = Date::ABBR_MONTHNAMES.index($1.capitalize)
        return Date.new($3.to_i, month, $2.to_i)
      end

      nil
    rescue ArgumentError => e
      Rails.logger.warn("Failed to parse date from: #{line.strip} — #{e.message}")
      nil
    end

    def extract_time_range(line)
      # "8:00AM-10:00AM" or "2:00PM - 6:00PM" (with optional spaces)
      if line =~ /(\d{1,2}):(\d{2})\s*(AM|PM)\s*-\s*(\d{1,2}):(\d{2})\s*(AM|PM)/i
        st = (convert_to_24h($1.to_i, $3.upcase) * 100) + $2.to_i
        et = (convert_to_24h($4.to_i, $6.upcase) * 100) + $5.to_i
        return [st, et]
      end

      # "9:00AM - 1PM" (end time without minutes)
      if line =~ /(\d{1,2}):(\d{2})\s*(AM|PM)\s*-\s*(\d{1,2})\s*(AM|PM)/i
        st = (convert_to_24h($1.to_i, $3.upcase) * 100) + $2.to_i
        et = convert_to_24h($4.to_i, $5.upcase) * 100
        return [st, et]
      end

      # Military time "0800-1000"
      if line =~ /\b(\d{4})\s*-\s*(\d{4})\b/
        return [$1.to_i, $2.to_i]
      end

      [nil, nil]
    end

    def convert_to_24h(hour, meridian)
      hour %= 12 if hour == 12
      hour += 12 if meridian == "PM"
      hour
    end

    def extract_location(line)
      # Guard: season+year strings (e.g. "SPRING 2026", "FALL 2025") look like a
      # valid building code + room number under the main regex below, but are page
      # headers that pdftotext sometimes emits as standalone lines between columns.
      return nil if line =~ /\A(?:SPRING|FALL|SUMMER|WINTER)\s+\d{4}\z/i

      # "ANXNO 201", "CEIS 414A/B", "WENTW 314"
      # Room number must start with a digit and be ≥3 chars to avoid false-
      # matching words ("SCHEDULE") or course suffixes like "01"/"02".
      if line =~ /([A-Z]{4,6})\s+(\d[\dA-Z]{2,}(?:\/[\dA-Z]+)*)\s*$/i
        building = $1
        rooms    = $2
        return rooms.include?("/") ? expand_room_list(building, rooms) : "#{building} #{rooms}"
      end

      # "WATSN Auditorium", "Sargent Hall"
      if line =~ /([A-Z][A-Za-z]+\s+(?:Auditorium|Hall|Center|Room))\s*$/
        return $1.strip
      end

      # Virtual / online
      return $1.upcase if line =~ /(ONLINE|TBA|VIRTUAL)/i

      # Faculty-administered — check before bare building code to avoid partial match
      return "SEE FACULTY" if line =~ /SEE FACULTY/i

      # Bare building code occupying the whole line (last resort)
      return $1 if line =~ /^([A-Z]{4,6})\s*$/

      nil
    end

    # Expands "002/004" → "BLDG 002 / BLDG 004" and "414A/B" → "BLDG 414A / BLDG 414B".
    def expand_room_list(building, rooms_str)
      parts = rooms_str.split("/")
      return "#{building} #{rooms_str}" if parts.length == 1

      base_number = nil
      parts.map do |part|
        if part =~ /^\d+/
          base_number = part[/^\d+/]
          "#{building} #{part}"
        elsif base_number && part =~ /^[A-Z]+$/i
          "#{building} #{base_number}#{part}"
        else
          "#{building} #{part}"
        end
      end.join(" / ")
    end

    # True for entries indicating no scheduled exam room/time (online, faculty-set, etc.)
    def no_exam_entry?(line)
      line.match?(/^(ONLINE|TBA|VIRTUAL|SEE FACULTY)/i)
    end

  end
end
