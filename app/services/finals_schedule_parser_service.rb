# frozen_string_literal: true

require "open3"
require "tempfile"

# Service to parse finals schedule PDFs and create FinalExam records
# Handles WIT's finals schedule PDF format which contains CRNs, dates, times, and locations
class FinalsScheduleParserService < ApplicationService
  attr_reader :pdf_content, :term

  # @param pdf_content [String] Raw PDF file content (binary string)
  # @param term [Term] The term this finals schedule belongs to
  def initialize(pdf_content:, term:)
    @pdf_content = pdf_content
    @term = term
    super()
  end

  def call
    validate!

    # Write content to temp file and extract text
    text = extract_pdf_text

    # Parse the text to find exam entries
    exam_entries = parse_exam_entries(text)

    # Create or update FinalExam records
    results = process_exam_entries(exam_entries)

    {
      total: exam_entries.count,
      created: results[:created],
      updated: results[:updated],
      skipped: results[:skipped],
      errors: results[:errors]
    }
  end

  private

  def validate!
    raise ArgumentError, "PDF content is required" if pdf_content.blank?
    raise ArgumentError, "Term is required" unless term.is_a?(Term)
    raise ArgumentError, "PDF content must be a string" unless pdf_content.is_a?(String)
  end

  def extract_pdf_text
    # Write PDF content to temp file, extract text with pdftotext, then clean up
    Tempfile.create(["finals_schedule", ".pdf"], binmode: true) do |tempfile|
      tempfile.write(pdf_content)
      tempfile.flush

      # Use Open3 for secure command execution (no shell injection)
      stdout, stderr, status = Open3.capture3("pdftotext", "-layout", tempfile.path, "-")

      unless status.success?
        error_msg = stderr.presence || "Unknown error"
        raise "Failed to extract text from PDF: #{error_msg}. Make sure pdftotext is installed (brew install poppler on Mac)"
      end

      stdout
    end
  end

  def parse_exam_entries(text)
    # Auto-detect format based on header structure
    format = detect_pdf_format(text)
    Rails.logger.info("Detected finals schedule PDF format: #{format}")

    case format
    when :fall_2025
      parse_fall_2025_format(text)
    when :spring_2025
      parse_spring_2025_format(text)
    else
      # Try both and return whichever gets more results
      fall_entries = parse_fall_2025_format(text)
      spring_entries = parse_spring_2025_format(text)

      if fall_entries.count >= spring_entries.count
        Rails.logger.info("Using Fall 2025 format (#{fall_entries.count} entries)")
        fall_entries
      else
        Rails.logger.info("Using Spring 2025 format (#{spring_entries.count} entries)")
        spring_entries
      end
    end
  end

  # Detect which PDF format we're dealing with based on header structure
  def detect_pdf_format(text)
    # Fall 2025 has "EXAM-DATE" and "EXAM-TIME-OF-DAY" headers
    # Spring 2025/Fall 2024 has "FINAL DAY" and "FINAL TIME" headers

    if text.match?(/EXAM-DATE.*EXAM-TIME/i)
      :fall_2025
    elsif text.match?(/FINAL\s+DAY.*FINAL\s+TIME/i)
      :spring_2025
    elsif text.match?(/MULTI-SECTION\s+CRNS/i)
      :spring_2025
    else
      :unknown
    end
  end

  # Fall 2025 format:
  # COURSE SECTION(S) | COURSE TITLE | COMBINED CRNs | INSTRUCTOR | EXAM-DATE | EXAM-TIME-OF-DAY | EXAM-ROOM
  # CRNs are dash-separated in a single column: "14572-14573-14574"
  def parse_fall_2025_format(text)
    entries = []

    text.each_line do |line|
      # Skip header/footer lines
      next if line.match?(/COURSE SECTION|FINAL EXAM|Page \d+|WENTWORTH INSTITUTE|EXAM-DATE|EXAM-TIME/i)
      next if line.strip.empty?

      # Look for lines with combined CRNs (dash-separated 5-digit numbers)
      # Pattern: multiple 5-digit numbers separated by dashes like "14572-14573-14574"
      if line =~ /(\d{5}(?:-\d{5})*)/
        combined_crns_str = $1
        crns = combined_crns_str.split("-").map(&:to_i)

        # Parse date (e.g., "Monday, December 8, 2025")
        date = extract_date(line)

        # Parse time range (e.g., "2:00PM-6:00PM" or "9:00AM - 1PM")
        start_time, end_time = extract_time_range(line)

        # Parse location (at end of line, after time)
        location = extract_location(line)

        # Skip lines without valid date/time (likely "SEE FACULTY FOR DETAILS")
        next unless date && start_time && end_time

        # Create an entry for each CRN in the combined list
        crns.each do |crn|
          entries << {
            crn: crn,
            combined_crns: crns,
            date: date,
            start_time: start_time,
            end_time: end_time,
            location: location
          }
        end
      end
    end

    entries
  end

  # Spring 2025/Fall 2024 format:
  # COURSE | SECTION | TITLE | CRN | MULTI-SECTION CRNS | INSTRUCTOR | FINAL DAY | FINAL TIME | FINAL LOCATION
  # Each row has a single CRN, with MULTI-SECTION CRNS in a separate dash-separated column
  def parse_spring_2025_format(text)
    entries = []

    text.each_line do |line|
      # Skip header/footer lines
      next if line.match?(/COURSE\s+NUMBER|FINAL EXAM|Page \d+|WENTWORTH INSTITUTE|FINAL\s+DAY|CRN\s+MULTI/i)
      next if line.strip.empty?

      # In this format, lines have a single 5-digit CRN followed by optional multi-section CRNs
      # The single CRN is standalone (not dash-prefixed), while multi-section CRNs are dash-separated
      # Pattern looks like: "COURSE  SECTION  TITLE    12345   12345-12346-12347   Instructor..."

      # First, check if this line has course-like data (contains a 5-digit number)
      next unless line =~ /\d{5}/

      # Extract the primary CRN - it's a standalone 5-digit number not preceded by another digit or dash
      # This distinguishes "12345" from "12345-12346" pattern
      primary_crn = nil
      combined_crns = []

      # Find standalone 5-digit number (primary CRN)
      # Look for a 5-digit number that's not part of a dash-separated group
      if line =~ /(?<![0-9-])(\d{5})(?![0-9])/
        primary_crn = $1.to_i
      end

      next unless primary_crn

      # Find the multi-section CRNs (dash-separated group)
      if line =~ /(\d{5}(?:-\d{5})+)/
        combined_crns = $1.split("-").map(&:to_i)
      else
        combined_crns = [primary_crn]
      end

      # Parse date (e.g., "Monday, April 14, 2025")
      date = extract_date(line)

      # Parse time range (e.g., "8:00AM-12:00PM")
      start_time, end_time = extract_time_range(line)

      # Parse location
      location = extract_location(line)

      # Skip lines without valid date/time
      next unless date && start_time && end_time

      entries << {
        crn: primary_crn,
        combined_crns: combined_crns,
        date: date,
        start_time: start_time,
        end_time: end_time,
        location: location
      }
    end

    entries
  end

  def extract_date(line)
    # Try different date formats
    # Format 1: MM/DD/YYYY
    if line =~ %r{(\d{1,2})/(\d{1,2})/(\d{4})}
      return Date.new($3.to_i, $1.to_i, $2.to_i)
    end
    
    # Format 2: Month DD, YYYY
    if line =~ /(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2}),?\s+(\d{4})/i
      month_name = $1
      day = $2.to_i
      year = $3.to_i
      month = Date::MONTHNAMES.index(month_name.capitalize)
      return Date.new(year, month, day)
    end
    
    # Format 3: Abbreviated month
    if line =~ /(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{1,2}),?\s+(\d{4})/i
      month_abbr = $1
      day = $2.to_i
      year = $3.to_i
      month = Date::ABBR_MONTHNAMES.index(month_abbr.capitalize)
      return Date.new(year, month, day)
    end
    
    nil
  rescue ArgumentError => e
    Rails.logger.warn("Failed to parse date from line: #{line.strip} - #{e.message}")
    nil
  end

  def extract_time_range(line)
    # Format 1: "8:00AM-10:00AM" or "2:00PM-6:00PM" (no space)
    if line =~ /(\d{1,2}):(\d{2})\s*(AM|PM)\s*-\s*(\d{1,2}):(\d{2})\s*(AM|PM)/i
      start_h = $1.to_i
      start_m = $2.to_i
      start_meridian = $3.upcase
      end_h = $4.to_i
      end_m = $5.to_i
      end_meridian = $6.upcase

      start_h = convert_to_24h(start_h, start_meridian)
      end_h = convert_to_24h(end_h, end_meridian)

      start_time = (start_h * 100) + start_m
      end_time = (end_h * 100) + end_m

      return [start_time, end_time]
    end

    # Format 2: "9:00AM - 1PM" (end time without minutes)
    if line =~ /(\d{1,2}):(\d{2})\s*(AM|PM)\s*-\s*(\d{1,2})\s*(AM|PM)/i
      start_h = $1.to_i
      start_m = $2.to_i
      start_meridian = $3.upcase
      end_h = $4.to_i
      end_m = 0
      end_meridian = $5.upcase

      start_h = convert_to_24h(start_h, start_meridian)
      end_h = convert_to_24h(end_h, end_meridian)

      start_time = (start_h * 100) + start_m
      end_time = (end_h * 100) + end_m

      return [start_time, end_time]
    end

    # Format 3: "0800-1000" (military time)
    if line =~ /(\d{4})\s*-\s*(\d{4})/
      start_time = $1.to_i
      end_time = $2.to_i
      return [start_time, end_time]
    end

    [nil, nil]
  end

  def convert_to_24h(hour, meridian)
    hour = hour % 12 if hour == 12
    hour += 12 if meridian == "PM"
    hour
  end

  # Expand room lists like "002/004" or "414A/B" into full room names
  # "002/004" -> ["BLDG 002", "BLDG 004"]
  # "414A/B" -> ["BLDG 414A", "BLDG 414B"] (B inherits the base number)
  def expand_room_list(building, rooms_str)
    parts = rooms_str.split("/")
    return "#{building} #{rooms_str}" if parts.length == 1

    expanded = []
    base_number = nil

    parts.each do |part|
      if part =~ /^\d+/
        # This part has a number, use it as the base
        base_number = part[/^\d+/]
        expanded << "#{building} #{part}"
      elsif base_number && part =~ /^[A-Z]+$/i
        # This is just a letter suffix (like "B" in "414A/B"), append to base
        expanded << "#{building} #{base_number}#{part}"
      else
        # Fallback: just use as-is
        expanded << "#{building} #{part}"
      end
    end

    expanded.join(" / ")
  end

  def extract_location(line)
    # WIT format has location at end of line after the time
    # Examples: "WATSN Auditorium", "ANXNO 201", "WENTW 212", "ANXSO 002/004", "CEIS 414A/B"

    # Pattern 1: Building code + complex room number (e.g., "ANXSO 002/004", "CEIS 414A/B", "WENTW 314")
    # Room can have digits, letters, slashes
    if line =~ /([A-Z]{4,6})\s+([\dA-Z]+(?:\/[\dA-Z]+)*)\s*$/i
      building = $1
      rooms = $2

      # Expand slashes to show multiple rooms
      if rooms.include?("/")
        return expand_room_list(building, rooms)
      else
        return "#{building} #{rooms}"
      end
    end

    # Pattern 2: Building name + Auditorium/Hall (e.g., "WATSN Auditorium", "Sargent Hall")
    if line =~ /([A-Z][A-Za-z]+\s+(?:Auditorium|Hall|Center|Room))\s*$/
      return $1.strip
    end

    # Pattern 3: Just a building code at end
    if line =~ /([A-Z]{4,6})\s*$/
      return $1
    end

    # Pattern 4: ONLINE/TBA/VIRTUAL anywhere in line
    if line =~ /(ONLINE|TBA|VIRTUAL)/i
      return $1.upcase
    end

    # Pattern 5: "SEE FACULTY" or similar
    if line =~ /SEE FACULTY/i
      return "SEE FACULTY"
    end

    nil
  end

  def process_exam_entries(entries)
    created = 0
    updated = 0
    linked = 0
    orphan = 0
    rooms_created = 0
    errors = []

    entries.each do |entry|
      # Ensure rooms exist in database
      rooms_created += ensure_rooms_exist(entry[:location])

      # Create or update final exam by CRN + term (not course)
      # This allows creating "orphan" exams for CRNs that don't have courses yet
      final_exam = FinalExam.find_or_initialize_by(crn: entry[:crn], term: term)
      was_new = final_exam.new_record?

      # Try to find and link to course if it exists
      course = Course.find_by(crn: entry[:crn], term: term)

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

    { created: created, updated: updated, linked: linked, orphan: orphan, rooms_created: rooms_created, errors: errors }
  end

  # Create rooms if they don't exist (when building exists)
  def ensure_rooms_exist(location)
    return 0 if location.blank?

    rooms_created = 0

    # Location format: "BLDG 123" or "BLDG 123 / BLDG 456"
    location.split(" / ").each do |loc|
      if loc =~ /([A-Z]+)\s+(\d+)([A-Z])?/i
        abbrev = $1
        room_num = $2.to_i
        suffix = $3 # Letter suffix like A, B (currently ignored for room creation)

        building = Building.find_by(abbreviation: abbrev)
        next unless building

        # Check if room exists, create if not
        unless building.rooms.exists?(number: room_num)
          building.rooms.create!(number: room_num)
          rooms_created += 1
          Rails.logger.info("Created room #{room_num} in #{building.name}")
        end
      end
    end

    rooms_created
  end
end
