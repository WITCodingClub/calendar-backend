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
  # - A chain that ends in "-" continues on the next CRN line of the same block
  #   (lines between blank lines).
  # - When the anchor line has no CRN (a tall row whose cells wrap, as in Fall
  #   2025), a CRN line with no date belongs to the nearest such anchor in its
  #   block, with no other anchor between them. An open chain goes to the
  #   anchor below it, and its next part goes to the same anchor. A CRN line
  #   with text in the date, time, or room columns is a row of its own.
  # - The room is the first cell after the time. Later cells are tags such as
  #   "COMBINED FINAL", which are never the room. A room too wide for its cell
  #   wraps to the lines above and below the row, to the right of the time.
  #   "SEE FACULTY", "ONLINE",
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
    TAG     = /\A\(?(?:MULTI-SECTION EXAM|COMBINED FINAL|DATE & TIME CHANGE)\)?\z/i

    def warnings
      @warnings ||= []
    end

    def parse(text)
      @warnings = []
      @lines    = text.to_s.delete("\f").lines.map(&:rstrip)
      @blocks   = block_ids
      anchors   = find_anchors
      @blank_rooms = anchors.reject { |a| room_cell(lines[a[:index]][a[:time].end(0)..]) }.to_set { |a| a[:index] }
      owned     = assign_crn_lines(anchors)
      rows      = anchors.filter_map { |anchor| build_row(anchor, owned[anchor[:index]]) }
      warn_unused_crn_lines(anchors, owned.values.flatten.to_set)

      unique_entries(build_entries(rows))
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

    def build_row(anchor, owned_lines)
      line   = lines[anchor[:index]]
      text   = [ crn_text(anchor), *owned_lines.to_a.map { |i| lines[i] } ].join("\n")
      groups = crn_groups(text)

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
        room:    room_cell(line[anchor[:time].end(0)..])
      }
    end

    def crn_text(anchor)
      lines[anchor[:index]][0...anchor[:date].begin(0)]
    end

    def room_cell(tail)
      cell = tail.to_s.strip.split(/\s{2,}/).first
      cell unless cell.nil? || cell.match?(TAG)
    end

    # Gives each CRN line that has no date (not an anchor) to the anchor it
    # belongs to. Returns { anchor line index => [line indexes] }.
    def assign_crn_lines(anchors)
      by_line    = anchors.index_by { |a| a[:index] }
      crnless    = anchors.select { |a| crn_groups(crn_text(a)).empty? }.to_set { |a| a[:index] }
      owned      = Hash.new { |hash, key| hash[key] = [] }
      open_owner = nil

      lines.each_with_index do |line, i|
        if (anchor = by_line[i])
          tokens = crn_text(anchor).scan(CRNS)
          open_owner = tokens.last&.end_with?("-") ? i : nil if tokens.any?
          next
        end
        next if !line.match?(CRNS) || line.match?(NO_EXAM)

        owner = if open_owner && @blocks[open_owner] == @blocks[i]
          open_owner
        else
          crnless_neighbor(anchors, crnless, i, below: line.scan(CRNS).last.end_with?("-"))
        end
        next open_owner = nil unless owner

        owned[owner] << i
        open_owner = line.scan(CRNS).last.end_with?("-") ? owner : nil
      end

      owned
    end

    # The anchor with no CRN just above or just below line i, in its block.
    # An open chain belongs to the anchor below it; any other line to the
    # nearer one, and to the one above on a tie.
    def crnless_neighbor(anchors, crnless, i, below:)
      after  = anchors.bsearch_index { |a| a[:index] > i }
      before = (after || anchors.size) - 1
      above  = anchors[before] if before >= 0
      under  = anchors[after] if after
      pool   = [ above, under ].compact.select do |a|
        # A line with text in the date, time, or room columns is a row of
        # its own (with no date), not part of a tall row.
        crnless.include?(a[:index]) && @blocks[a[:index]] == @blocks[i] &&
          lines[i][a[:date].begin(0)..].to_s.strip.empty?
      end

      return pool.find { |a| a[:index] > i }&.dig(:index) if below

      pool.min_by { |a| [ (a[:index] - i).abs, a[:index] > i ? 1 : 0 ] }&.dig(:index)
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

    def warn_unused_crn_lines(anchors, used)
      anchor_lines = anchors.to_set { |a| a[:index] }

      lines.each_with_index do |line, i|
        next if anchor_lines.include?(i) || used.include?(i)
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

    # A wrapped room has its first part on the line above the row and the rest
    # on the line below.
    def wrapped_room(row)
      time_at = row[:time].begin(0)

      [ row[:index] - 1, row[:index] + 1 ]
        .select { |i| fragment_owner(i, time_at) == row[:index] }
        .filter_map { |i| room_fragment(i, time_at) }
        .join(" ")
    end

    # The row with an empty room cell that a room part belongs to. A part
    # between two such rows belongs to the upper row when that row also has a
    # part above it (the part is its lower half), and to the lower row if not.
    def fragment_owner(i, time_at)
      return unless room_fragment(i, time_at)

      up   = @blank_rooms.include?(i - 1) ? i - 1 : nil
      down = @blank_rooms.include?(i + 1) ? i + 1 : nil
      return up || down unless up && down

      room_fragment(up - 1, time_at) ? up : down
    end

    def room_fragment(i, time_at)
      line = lines[i] if i >= 0
      return if line.nil? || line.match?(CRNS) || line.match?(DATE)

      line.strip.presence if line[/\A */].size > time_at
    end

    # Duplicate rows for a CRN: the first row wins. A later row with other
    # data gets a warning, so a correction lower in the PDF is not lost
    # silently.
    def unique_entries(entries)
      first = {}
      entries.each do |entry|
        kept = first[entry[:crn]]
        next first[entry[:crn]] = entry unless kept

        if kept.except(:combined_crns) != entry.except(:combined_crns)
          warn("CRN #{entry[:crn]} has more than one row with different data; used the first row")
        end
      end
      first.values
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
