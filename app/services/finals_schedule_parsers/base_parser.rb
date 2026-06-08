# frozen_string_literal: true

module FinalsScheduleParsers
  class BaseParser
    def self.matches?(_text)
      raise NotImplementedError, "#{name}.matches? must be implemented"
    end

    def parse(_text)
      raise NotImplementedError, "#{self.class}#parse must be implemented"
    end

    private

    def preprocess_text(text)
      text
        .gsub(/^\*\s+/, "")
        .gsub(/Date & Time Change\s*$/i, "")
        .gsub(/FINAL SCHEDULE INFORMATION.*$/i, "")
        .gsub(/Schedule as of [\d\/]+\s*$/i, "")
        .gsub(/UPDATED\s+(?=FALL|SPRING|SUMMER)/i, "")
    end

    def extract_date(line)
      if line =~ /(\d{1,2})\/(\d{1,2})\/(\d{4})/
        return Date.new($3.to_i, $1.to_i, $2.to_i)
      end

      if line =~ %r{(January|February|March|April|May|June|July|August|
                   September|October|November|December)\s+(\d{1,2}),?\s+(\d{4})}xi
        month = Date::MONTHNAMES.index($1.capitalize)
        return Date.new($3.to_i, month, $2.to_i)
      end

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
      if line =~ /(\d{1,2}):(\d{2})\s*(AM|PM)\s*-\s*(\d{1,2}):(\d{2})\s*(AM|PM)/i
        st = (convert_to_24h($1.to_i, $3.upcase) * 100) + $2.to_i
        et = (convert_to_24h($4.to_i, $6.upcase) * 100) + $5.to_i
        return [st, et]
      end

      if line =~ /(\d{1,2}):(\d{2})\s*(AM|PM)\s*-\s*(\d{1,2})\s*(AM|PM)/i
        st = (convert_to_24h($1.to_i, $3.upcase) * 100) + $2.to_i
        et = convert_to_24h($4.to_i, $5.upcase) * 100
        return [st, et]
      end

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
      return nil if line =~ /\A(?:SPRING|FALL|SUMMER|WINTER)\s+\d{4}\z/i
      return nil if line =~ /\A[A-Z]{2,6}\s+\d{4}\z/

      if line =~ /([A-Z]{4,6})\s+(AUD|\d[\dA-Z]{2,}(?:\/[\dA-Z]+)*)\s*$/i
        building = $1
        rooms    = $2
        return rooms.include?("/") ? expand_room_list(building, rooms) : "#{building} #{rooms}"
      end

      if line =~ /([A-Z][A-Za-z]+\s+(?:Auditorium|Hall|Center|Room))\s*$/
        return $1.strip
      end

      return $1.upcase if line =~ /(ONLINE|TBA|VIRTUAL)/i
      return "SEE FACULTY" if line =~ /SEE FACULTY/i

      nil
    end

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

    def no_exam_entry?(line)
      line.match?(/^(ONLINE|TBA|VIRTUAL|SEE FACULTY)/i)
    end
  end
end
