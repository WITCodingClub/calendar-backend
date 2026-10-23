# frozen_string_literal: true

module FinalsSchedules
  # Reads the exam table from `pdftotext -layout` text. Every WIT finals PDF
  # from 2022 on prints one exam per row, but the columns, headers, and page
  # breaks change each term, so the parser finds a row by its content, not by
  # column position:
  #
  # - A row has a weekday date and a time range on one line (the anchor).
  # - Its CRNs are the CRN tokens before the date on that line. A chain such as
  #   "10001-10002" is the group of CRNs that take one exam together.
  # - When the anchor line has no CRN (a tall row whose cells wrap, as in Fall
  #   2025), the CRNs come from the lines of the same block (lines between blank
  #   lines) that sit between the previous and the next anchor. A chain that
  #   ends in "-" continues on the next line.
  # - The room is the first cell after the time. Later cells are tags such as
  #   "COMBINED FINAL". A room too wide for its cell wraps to the lines above
  #   and below the row, to the right of the time. "SEE FACULTY", "ONLINE",
  #   "VIRTUAL", and "TBA" in the room cell become "See Faculty", "Online",
  #   "Virtual", and "TBA".
  #
  # Some PDFs have the wrong year on a few rows (a spreadsheet fill-down counted
  # the year up). The parser uses the year that most rows use when the printed
  # weekday agrees with that date, and the printed year only when it does not.
  class TableParser
    MONTHS  = Date::MONTHNAMES.compact.join("|")
    DATE    = /(?<weekday>(?:MON|TUES|WEDNES|THURS|FRI|SATUR|SUN)DAY),?\s+(?<month>#{MONTHS})\s+(?<day>\d{1,2}),?\s+(?<year>\d{4})/i
    CLOCK   = /(\d{1,2})(?::(\d{2}))?\s*([AP]M)/i
    TIME    = /#{CLOCK}\s*-\s*#{CLOCK}/
    CRNS    = /(?<![\d-])\d{5}(?:-\d{5})*-?(?!\d)/
    NO_EXAM = %r{\b(?:ONLINE|TBA|VIRTUAL|SEE FACULTY)\b|#N/A}i
    LOCATION_LABELS = {
      "ONLINE"      => "Online",
      "TBA"         => "TBA",
      "VIRTUAL"     => "Virtual",
      "SEE FACULTY" => "See Faculty"
    }.freeze
    ROOM    = %r{\A([A-Z0-9]*[A-Z])\s*(\d{3}[A-Z]?(?:/[0-9A-Z]+)*)\z}

    def warnings
      @warnings ||= []
    end

    def parse(text)
      @warnings = []
      @lines    = text.to_s.delete("\f").lines.map(&:rstrip)
      @blocks   = block_ids
      @used     = Set.new
      anchors   = find_anchors
      rows      = anchors.each_index.filter_map { |k| build_row(anchors, k) }
      warn_unused_crn_lines(anchors)

      build_entries(rows).uniq { |entry| entry[:crn] }
    end

    private

    attr_reader :lines

    def block_ids
      id = 0
      lines.map do |line|
        next id unless line.strip.empty?

        id += 1
        nil
      end
    end

    def find_anchors
      lines.each_with_index.filter_map do |line, i|
        date = DATE.match(line) or next
        time = TIME.match(line, date.end(0)) or next

        { index: i, date: date, time: time }
      end
    end

    def build_row(anchors, k)
      anchor = anchors[k]
      line   = lines[anchor[:index]]
      groups = crn_groups(line[0...anchor[:date].begin(0)])
      groups = crn_groups_near(anchors, k) if groups.empty?

      if groups.empty?
        warn("Row has no CRN: #{line.squish}")
        return
      end

      {
        index:   anchor[:index],
        groups:  groups,
        weekday: anchor[:date][:weekday].capitalize,
        month:   Date::MONTHNAMES.index(anchor[:date][:month].capitalize),
        day:     anchor[:date][:day].to_i,
        year:    anchor[:date][:year].to_i,
        time:    anchor[:time],
        room:    line[anchor[:time].end(0)..].to_s.strip.split(/\s{2,}/).first
      }
    end

    # CRN groups from the lines of the anchor's block between its neighbors.
    def crn_groups_near(anchors, k)
      index = anchors[k][:index]
      from  = k.zero? ? 0 : anchors[k - 1][:index] + 1
      to    = anchors[k + 1] ? anchors[k + 1][:index] - 1 : lines.size - 1
      near  = (from..to).select { |i| i != index && @blocks[i] == @blocks[index] && lines[i].match?(CRNS) }
      @used.merge(near)
      crn_groups(near.map { |i| lines[i] }.join("\n"))
    end

    # CRN groups in reading order. A chain that ends in "-" continues in the
    # next token.
    def crn_groups(text)
      groups = []
      open   = false
      text.scan(CRNS) do
        token = Regexp.last_match(0)
        crns  = token.scan(/\d{5}/).map(&:to_i)
        open && groups.any? ? groups.last.concat(crns) : groups << crns
        open = token.end_with?("-")
      end
      groups.map(&:uniq)
    end

    def warn_unused_crn_lines(anchors)
      anchor_lines = anchors.to_set { |a| a[:index] }

      lines.each_with_index do |line, i|
        next if anchor_lines.include?(i) || @used.include?(i)
        next if !line.match?(CRNS) || line.match?(NO_EXAM)

        warn("Row has no exam date and time: #{line.squish}")
      end
    end

    def build_entries(rows)
      year      = rows.map { |row| row[:year] }.tally.max_by { |_, count| count }&.first
      corrected = []

      entries = rows.flat_map do |row|
        date = resolve_date(row, year)
        next [] unless date

        corrected << row[:groups].flatten.first if date.year != row[:year]
        start_time, end_time = clock_times(row[:time])
        location = normalize_location(row[:room].presence || wrapped_room(row))

        singles, chains = row[:groups].partition { |group| group.size == 1 }
        combined = chains.first || singles.flatten.uniq
        crns     = singles.any? ? singles.first : combined

        crns.map do |crn|
          { crn: crn, combined_crns: combined, date: date,
            start_time: start_time, end_time: end_time, location: location }
        end
      end

      if corrected.any?
        warn("#{corrected.size} rows had a year other than #{year}; used #{year} for CRNs #{corrected.join(', ')}")
      end

      entries
    end

    def resolve_date(row, year)
      [ year, row[:year] ].uniq.each do |y|
        date = Date.new(y, row[:month], row[:day])
        return date if date.strftime("%A") == row[:weekday]
      rescue Date::Error
        next
      end

      warn("CRN #{row[:groups].flatten.first}: #{row[:weekday]}, #{Date::MONTHNAMES[row[:month]]} #{row[:day]}, " \
           "#{row[:year]} has a weekday that does not match the date; row skipped")
      nil
    end

    def clock_times(match)
      [ match.values_at(1, 2, 3), match.values_at(4, 5, 6) ].map do |hour, minute, meridian|
        hour = hour.to_i % 12
        hour += 12 if meridian.upcase == "PM"
        (hour * 100) + minute.to_i
      end
    end

    def wrapped_room(row)
      time_at = row[:time].begin(0)

      [ row[:index] - 1, row[:index] + 1 ].filter_map do |i|
        line = lines[i] if i >= 0
        next if line.nil? || line.match?(CRNS) || line.match?(DATE)

        line.strip.presence if line[/\A */].size > time_at
      end.join(" ")
    end

    # "WENTW212" becomes "WENTW 212" and "CEIS 414A/B" becomes
    # "CEIS 414A / CEIS 414B", so FinalExam::ROOM_PATTERN finds each room. A
    # building with no room ("WATSN") or a named space ("ANXNO CRIT RM") stays
    # as it is. A no-exam marker becomes its title-case label ("SEE FACULTY FOR
    # DETAILS" becomes "See Faculty"). "#N/A" is a spreadsheet error, not a
    # place, so it gives no location.
    def normalize_location(room)
      return if room.blank? || room.include?("#N/A")

      marker = room[NO_EXAM]
      return LOCATION_LABELS.fetch(marker.upcase) if marker

      room = room.squish
      return room unless room =~ ROOM

      building = Regexp.last_match(1)
      base     = nil
      Regexp.last_match(2).split("/").map do |part|
        if part.match?(/\A\d/)
          base = part[/\A\d+/]
          "#{building} #{part}"
        else
          "#{building} #{base}#{part}"
        end
      end.join(" / ")
    end

    def warn(message)
      message = "Finals PDF: #{message}"
      Rails.logger.warn(message)
      warnings << message
    end
  end
end
