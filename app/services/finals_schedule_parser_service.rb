# frozen_string_literal: true

require "open3"
require "tempfile"

# Service to parse finals schedule PDFs and create FinalExam records.
#
# Handles three distinct WIT PDF formats:
#
#   :spring_fall — Fall 2024, Spring 2025, Summer 2025
#     Each table row appears as one line in pdftotext output.
#     Columns: COURSE NUMBER | SECTION | TITLE | CRN | MULTI-SECTION CRNS |
#              INSTRUCTOR | FINAL DAY/DATE | FINAL TIME | FINAL LOCATION
#     Quirks:
#       - Summer 2025 uses "FINAL DATE" instead of "FINAL DAY"
#       - Amended Spring 2025 PDFs have a leading "* " on updated rows
#       - Fall 2024: only some rows in a shared-CRN group include date/time;
#         fix is to expand to ALL combined CRNs whenever a dated row is found
#
#   :fall_2025 — Fall 2025 and future semesters using the new template
#     pdftotext renders the wide table as *column blocks*: all CRNs appear
#     together, then all exam dates, then all times, then all locations.
#     Each positional slot i across the four blocks belongs to one exam group.
#     Parsing strategy: identify each block type, then zip by position.
#
class FinalsScheduleParserService < ApplicationService
  attr_reader :pdf_content, :term

  # @param pdf_content [String] Raw PDF binary string
  # @param term [Term]         The academic term this schedule belongs to
  def initialize(pdf_content:, term:)
    @pdf_content = pdf_content
    @term = term
    super()
  end

  def call
    validate!

    text         = extract_pdf_text
    exam_entries = parse_exam_entries(text)
    results      = process_exam_entries(exam_entries)

    {
      total: exam_entries.count,
      created: results[:created],
      updated: results[:updated],
      linked: results[:linked],
      orphan: results[:orphan],
      rooms_created: results[:rooms_created],
      errors: results[:errors]
    }
  end

  private

  def validate!
    raise ArgumentError, "PDF content is required"           if pdf_content.blank?
    raise ArgumentError, "Term is required"                  unless term.is_a?(Term)
    raise ArgumentError, "PDF content must be a string"      unless pdf_content.is_a?(String)
  end

  def extract_pdf_text
    Tempfile.create(["finals_schedule", ".pdf"], binmode: true) do |tmp|
      tmp.write(pdf_content)
      tmp.flush

      stdout, stderr, status = Open3.capture3("pdftotext", tmp.path, "-")

      unless status.success?
        raise "Failed to extract text from PDF: #{stderr.presence || 'Unknown error'}. " \
              "Make sure pdftotext is installed (brew install poppler on Mac)"
      end

      stdout
    end
  end

  # ---------------------------------------------------------------------------
  # Top-level entry point
  # ---------------------------------------------------------------------------

  def parse_exam_entries(text)
    normalized = preprocess_text(text)
    format     = detect_pdf_format(normalized)
    Rails.logger.info("Detected finals schedule PDF format: #{format}")

    case format
    when :fall_2025
      parse_fall_2025_format(normalized)
    when :spring_fall
      parse_spring_fall_format(normalized)
    else
      fall_entries   = parse_fall_2025_format(normalized)
      spring_entries = parse_spring_fall_format(normalized)

      if fall_entries.count >= spring_entries.count
        Rails.logger.info("Using fall_2025 format (#{fall_entries.count} entries)")
        fall_entries
      else
        Rails.logger.info("Using spring_fall format (#{spring_entries.count} entries)")
        spring_entries
      end
    end
  end

  # Strip common PDF artefacts that trip up the parsers.
  def preprocess_text(text)
    text
      .gsub(/^\*\s+/, "") # "* ARCH1500..." → "ARCH1500..."
      .gsub(/Date & Time Change\s*$/i, "")            # amendment annotation column
      .gsub(/FINAL SCHEDULE INFORMATION.*$/i, "")     # info column header/content
      .gsub(/Schedule as of [\d\/]+\s*$/i, "")        # footer datestamp
      .gsub(/UPDATED\s+(?=FALL|SPRING|SUMMER)/i, "")  # "UPDATED FALL 2025" → "FALL 2025"
  end

  # Detect the PDF template in use.
  def detect_pdf_format(text)
    if text.match?(/EXAM-DATE|EXAM-TIME-OF-DAY|COMBINED\s+CRNs/i)
      :fall_2025
    elsif text.match?(/FINAL\s+(DAY|DATE)|MULTI-SECTION\s+CRNS/i)
      :spring_fall
    else
      :unknown
    end
  end

  # ===========================================================================
  # Fall 2025 format — column-block zipper
  #
  # pdftotext outputs all CRN lines together, then all date lines, then all
  # time lines, then all location lines (because the PDF stores its wide table
  # in column order).  We identify each "block" (a contiguous run of lines that
  # all classify as the same data type) and zip same-sized blocks in the order
  # CRN → date → time → location.
  # ===========================================================================

  def parse_fall_2025_format(text)
    lines = text
            .lines
            .map(&:strip)
            .reject { |l| l.empty? || fall_2025_header_line?(l) }

    classified = lines.map { |l| { line: l, type: classify_fall_line(l) } }

    crn_blocks      = extract_typed_blocks(classified, :crn)
    date_blocks     = extract_typed_blocks(classified, :date)
    time_blocks     = extract_typed_blocks(classified, :time)
    location_blocks = extract_typed_blocks(classified, :location)

    entries = []

    date_blocks.each do |date_block|
      n = date_block[:data].size

      # Nearest preceding CRN block of the same row count
      crn_block = crn_blocks
                  .select { |b| b[:end_idx] < date_block[:start_idx] && b[:data].size == n }
                  .last
      next unless crn_block

      # Nearest following time block of the same row count
      time_block = time_blocks
                   .select { |b| b[:start_idx] > date_block[:start_idx] && b[:data].size == n }
                   .first
      next unless time_block

      # Nearest following location block of the same row count (optional)
      location_block = location_blocks
                       .select { |b| b[:start_idx] > time_block[:start_idx] && b[:data].size == n }
                       .first

      n.times do |i|
        crns       = crn_block[:data][i]
        date       = date_block[:data][i]
        st, et     = time_block[:data][i]
        location   = location_block&.dig(:data, i)

        next unless date && st && et
        next if crns.empty?

        crns.each do |crn|
          entries << {
            crn: crn,
            combined_crns: crns,
            date: date,
            start_time: st,
            end_time: et,
            location: location
          }
        end
      end
    end

    # Keep only the first entry per CRN (earliest in PDF order wins)
    seen = {}
    entries.select { |e| seen[e[:crn]] ? false : (seen[e[:crn]] = true) }
  end

  # Classifies a single line for the Fall 2025 block-based parser.
  def classify_fall_line(line)
    return :crn      if crn_only_line?(line)
    return :date     if date_only_line?(line)
    return :time     if time_only_line?(line)
    return :location if location_only_line?(line)

    :other
  end

  # True when the entire line is one or more 5-digit CRNs separated by dashes.
  # Handles merged pairs like "1458814589" (pdftotext drops the separator when
  # two CRN columns wrap at the same position).
  def crn_only_line?(line)
    normalized = normalize_merged_crns(line)
    normalized.match?(/^\d{5}(-\d{5})*$/)
  end

  # True when the line opens with a weekday name (i.e. it IS a date).
  def date_only_line?(line)
    line.match?(/^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),/i)
  end

  # True when the line is purely a time range with no other content.
  def time_only_line?(line)
    st, _et = extract_time_range(line)
    return false unless st
    return false if date_only_line?(line)           # "Wednesday, Dec 10 … 10:15AM-12:15PM"
    return false if line.match?(/[A-Z]{4,6}\s+\S/)  # contains a building code → location

    true
  end

  # True when the line is a standalone WIT building location.
  # Uses anchored patterns to avoid false-matching course titles like "STUDIO 01".
  def location_only_line?(line)
    # "WENTW 212", "ANXCN 014", "CEIS 414A/B" — room must be ≥3 chars to rule
    # out course-title suffixes like "01", "02"
    return true if line.match?(/^[A-Z]{4,6}\s+[\dA-Z]{3,}(?:\/[\dA-Z]+)*\s*$/i)

    # "WATSN Auditorium", "Sargent Hall"
    return true if line.match?(/^[A-Z][A-Za-z]+\s+(?:Auditorium|Hall|Center|Room)\s*$/i)

    # Online / TBA / see faculty
    return true if line.match?(/^(ONLINE|TBA|VIRTUAL|SEE FACULTY)/i)

    false
  end

  # Groups consecutive lines of `type` into blocks.
  # Returns an array of { start_idx:, end_idx:, data: [...] }
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

  # Extracts all 5-digit CRNs from a line (after normalizing merged pairs).
  def parse_crn_line(line)
    normalize_merged_crns(line)
      .scan(/\d{5}(?:-\d{5})*/)
      .flat_map { |m| m.split("-").map(&:to_i) }
      .select { |n| n >= 10_000 }
      .uniq
  end

  # Splits merged 10-digit CRN pairs, e.g. "1458814589" → "14588-14589".
  def normalize_merged_crns(line)
    line.gsub(/(\d{5})(\d{5})/, '\1-\2')
  end

  def fall_2025_header_line?(line)
    line.match?(%r{COURSE SECTION|COMBINED CRNs|EXAM-DATE|EXAM-TIME|EXAM-ROOM|
                 FALL \d{4} FINAL|Page \d+}xi)
  end

  # ===========================================================================
  # Spring / Fall / Summer format — CRN-anchored state machine
  #
  # All PDFs in this family render as column-per-line: each field value is on
  # its own line, fields for successive rows are interleaved.  We anchor on
  # standalone 5-digit CRN lines and scan forward for date → time → location.
  #
  # Spring 2025 / Fall 2024: each course has an individual CRN line followed
  # immediately by a combined-chain line ("27975-27976-..."); we use the chain
  # for combined_crns and consume both lines as one record.
  #
  # Summer 2025: each course has only an individual CRN (no chain).
  #
  # Fall 2024 backfill: some rows in a shared-CRN group omit date/time; after
  # building all records we fill in missing date/time from a sibling that has it.
  # ===========================================================================

  def parse_spring_fall_format(text)
    lines = text.lines.map(&:strip).reject(&:empty?)
    records = []
    i = 0

    while i < lines.size
      line = lines[i]

      # Only anchor on a standalone 5-digit CRN
      if line.match?(/^\d{5}$/)
        crn           = line.to_i
        combined_crns = [crn]
        j             = i + 1

        # Spring 2025 / Fall 2024: the next line is the combined CRN chain
        if j < lines.size && lines[j].match?(/^\d{5}(-\d{5})+$/)
          combined_crns = lines[j].split("-").map(&:to_i)
          j += 1
        end

        # Scan ahead for date → time → location, stop at the next CRN
        date       = nil
        start_time = nil
        end_time   = nil
        location   = nil
        date_found = false

        while j < lines.size
          break if lines[j].match?(/^\d{5}$/) # next course CRN — stop

          if !date_found && (parsed = extract_date(lines[j]))
            date = parsed
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
              break # got everything we need for this course
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
    # group.  Handles Fall 2024 where only some rows carry date/time.
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

  # ===========================================================================
  # Shared helpers — date, time, location extraction
  # ===========================================================================

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
    # "8:00AM-10:00AM" or "2:00PM - 6:00PM"
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
    # "ANXNO 201", "CEIS 414A/B", "WENTW 314"
    if line =~ /([A-Z]{4,6})\s+([\dA-Z]+(?:\/[\dA-Z]+)*)\s*$/i
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

    # Faculty-administered — must come before bare-code pattern to avoid
    # "ACULTY" being captured as a 6-char substring of "FACULTY"
    return "SEE FACULTY" if line =~ /SEE FACULTY/i

    # Bare building code at end (last resort)
    if line =~ /([A-Z]{4,6})\s*$/
      return $1
    end

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

  # ===========================================================================
  # Database persistence
  # ===========================================================================

  def process_exam_entries(entries)
    created = updated = linked = orphan = rooms_created = 0
    errors  = []

    entries.each do |entry|
      rooms_created += ensure_rooms_exist(entry[:location])

      final_exam = FinalExam.find_or_initialize_by(crn: entry[:crn], term: term)
      was_new    = final_exam.new_record?
      course     = Course.find_by(crn: entry[:crn], term: term)

      final_exam.assign_attributes(
        course: course,
        exam_date: entry[:date],
        start_time: entry[:start_time],
        end_time: entry[:end_time],
        location: entry[:location],
        combined_crns: entry[:combined_crns]
      )

      if final_exam.save
        was_new ? created += 1 : updated += 1
        course ? linked += 1 : orphan += 1
      else
        errors << "Failed to save final exam for CRN #{entry[:crn]}: #{final_exam.errors.full_messages.join(', ')}"
      end
    rescue => e
      errors << "Error processing CRN #{entry[:crn]}: #{e.message}"
    end

    { created: created, updated: updated, linked: linked, orphan: orphan,
      rooms_created: rooms_created, errors: errors
}
  end

  # Creates Room records for any building/room combos that don't exist yet.
  def ensure_rooms_exist(location)
    return 0 if location.blank?

    rooms_created = 0

    location.split(" / ").each do |loc|
      next unless loc =~ /([A-Z]+)\s+(\d+)([A-Z])?/i

      building = Building.find_by(abbreviation: $1)
      next unless building
      next if building.rooms.exists?(number: $2.to_i)

      building.rooms.create!(number: $2.to_i)
      rooms_created += 1
      Rails.logger.info("Created room #{$2} in #{building.name}")
    end

    rooms_created
  end

end
