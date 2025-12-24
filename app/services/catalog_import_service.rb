# frozen_string_literal: true

# Service to import courses from catalog data into the database
# Unlike CourseProcessorService, this doesn't create user enrollments
class CatalogImportService < ApplicationService
  include ApplicationHelper

  attr_reader :catalog_courses

  def initialize(catalog_courses)
    @catalog_courses = catalog_courses
    super()
  end

  def call
    validate_courses_data!

    processed_count = 0
    failed_courses = []

    # Deduplicate courses by CRN and term
    unique_courses = catalog_courses.uniq { |c| [c["courseReferenceNumber"], c["term"]] }

    # Track which terms we're importing (handle both possible field names)
    term_uids = unique_courses.map { |c| c["term"] || c["termEffective"] }.compact.uniq

    unique_courses.each_with_index do |course_data, index|
      begin
        process_course(course_data)
        processed_count += 1
      rescue => e
        Rails.logger.error("Failed to process course #{course_data['courseReferenceNumber']}: #{e.message}")
        failed_courses << {
          crn: course_data["courseReferenceNumber"],
          term: course_data["term"],
          error: e.message
        }
      end

      # Log progress every 50 courses
      if (index + 1) % 50 == 0
        Rails.logger.info("Processed #{index + 1}/#{unique_courses.count} courses")
      end
    end

    # Mark terms as imported
    term_uids.each do |term_uid|
      term = Term.find_by(uid: term_uid)
      if term && processed_count > 0
        term.update!(
          catalog_imported: true,
          catalog_imported_at: Time.current
        )
        Rails.logger.info("Marked term #{term_uid} (#{term.name}) as catalog_imported")
      end
    end

    {
      total: unique_courses.count,
      processed: processed_count,
      failed: failed_courses.count,
      failed_courses: failed_courses
    }
  end

  def call!
    result = call
    raise "Failed to process #{result[:failed]} courses" if result[:failed] > 0

    result
  end

  private

  def process_course(course_data)
    # Handle both possible field name variations from different API endpoints
    crn = course_data["courseReferenceNumber"] || course_data["crn"]
    term_uid = course_data["term"] || course_data["termEffective"]

    # Look up term by UID
    term = Term.find_by(uid: term_uid)
    unless term
      raise "Term with UID #{term_uid} not found. Please create the term first."
    end

    # Parse schedule type to get code in parentheses
    # e.g., "Lecture (LEC)" -> "LEC"
    schedule_type_desc = course_data["scheduleTypeDescription"] || course_data["scheduleType"]
    schedule_type_match = schedule_type_desc.to_s.match(/\(([^)]+)\)/)

    # Extract meeting times and faculty from bulk catalog data (if available)
    meeting_times = []
    if course_data["meetingsFaculty"].is_a?(Array)
      course_data["meetingsFaculty"].each do |session|
        meeting_time = session["meetingTime"]
        meeting_times << meeting_time if meeting_time.present?
      end
    end

    # Get start/end dates from first meeting time, with validation
    start_date = nil
    end_date = nil
    if meeting_times.any?
      first_meeting = meeting_times.first
      # Parse dates from MM/DD/YYYY format
      parsed_start = parse_date(first_meeting["startDate"])
      parsed_end = parse_date(first_meeting["endDate"])

      # Validate dates are reasonable for the term year (within 1 year tolerance)
      if dates_valid_for_term?(parsed_start, parsed_end, term)
        start_date = parsed_start
        end_date = parsed_end
      else
        Rails.logger.warn("Invalid dates for term #{term.name}: #{parsed_start} to #{parsed_end}, using term defaults")
        start_date = term.start_date
        end_date = term.end_date
      end
    end

    # Create or update course using bulk catalog data
    course = Course.find_or_create_by!(crn: crn) do |c|
      c.title = titleize_with_roman_numerals(course_data["courseTitle"] || "Untitled Course")
      c.subject = course_data["subject"] || course_data["subjectCode"]
      c.course_number = course_data["courseNumber"]
      c.schedule_type = schedule_type_match ? schedule_type_match[1] : nil
      c.section_number = course_data["sequenceNumber"] || course_data["sectionNumber"]

      # LeopardWeb shows total course credit hours for all sections (lecture + lab)
      # Labs are typically 0-credit companion sections, so override for LAB schedule type
      c.credit_hours = (schedule_type_match && schedule_type_match[1] == "LAB") ? 0 : course_data["creditHours"]
      c.grade_mode = nil # Not available in bulk catalog data
      c.start_date = start_date
      c.end_date = end_date
      c.term = term
    end

    # Update dates if course already exists
    if course.persisted? && !course.new_record? && start_date.present? && end_date.present?
      course.update!(
        start_date: start_date,
        end_date: end_date
      )
    end

    # Link orphan FinalExam records to this course (if finals schedule was uploaded before courses)
    orphan_exam = FinalExam.orphan.find_by(crn: course.crn, term: term)
    if orphan_exam
      orphan_exam.update!(course: course)
      Rails.logger.info("Linked FinalExam for CRN #{course.crn} to course #{course.id}")
    end

    # Ingest meeting times (only if we have them)
    if meeting_times.any?
      MeetingTimesIngestService.call(
        course: course,
        raw_meeting_times: meeting_times
      )
    else
      Rails.logger.warn("No meeting times found for course CRN #{crn}")
    end

    # Process and associate faculty with the course (only if we have them)
    faculty_data = course_data["faculty"] || []
    if faculty_data.any?
      process_faculty(course, faculty_data)
    else
      Rails.logger.warn("No faculty data found for course CRN #{crn}")
    end

    course
  end

  def validate_courses_data!
    raise ArgumentError, "catalog_courses cannot be nil" if catalog_courses.nil?
    raise ArgumentError, "catalog_courses must be an array" unless catalog_courses.is_a?(Array)
    raise ArgumentError, "catalog_courses cannot be empty" if catalog_courses.empty?

    catalog_courses.each_with_index do |course_data, index|
      unless course_data.is_a?(Hash)
        raise ArgumentError, "course at index #{index} must be a hash"
      end

      # Check for CRN in either possible field name
      crn = course_data["courseReferenceNumber"] || course_data["crn"]
      if crn.blank?
        available_keys = course_data.keys.first(15).join(", ")
        raise ArgumentError, "course at index #{index} missing required field: courseReferenceNumber or crn. Available keys: #{available_keys}"
      end

      # Check for term in either possible field name
      term_uid = course_data["term"] || course_data["termEffective"]
      if term_uid.blank?
        raise ArgumentError, "course at index #{index} missing required field: term or termEffective"
      end

      # Validate term UID is numeric
      unless term_uid.to_s.match?(/^\d+$/)
        raise ArgumentError, "course at index #{index} has invalid term UID: #{term_uid}"
      end
    end
  end

  def process_faculty(course, faculty_data)
    # Deduplicate faculty by email
    unique_faculty = faculty_data.uniq { |f| f["emailAddress"] || f[:emailAddress] }

    # Preload existing faculty IDs to avoid N+1 queries
    existing_faculty_ids = course.faculty_ids.to_set

    unique_faculty.each do |faculty_info|
      next if faculty_info.blank?

      # Extract faculty details (support both string and symbol keys)
      email = (faculty_info["emailAddress"] || faculty_info[:emailAddress]).to_s.strip
      display_name = (faculty_info["displayName"] || faculty_info[:displayName]).to_s.strip

      # Skip if no email
      next if email.blank?

      # Parse name (usually in format "Last, First" or "First Last")
      first_name, last_name = parse_faculty_name(display_name)
      next if first_name.blank? || last_name.blank?

      # Find or create faculty
      faculty = Faculty.find_or_create_by!(email: email) do |f|
        f.first_name = first_name
        f.last_name = last_name
      end

      # Associate with course
      unless existing_faculty_ids.include?(faculty.id)
        course.faculties << faculty
        existing_faculty_ids.add(faculty.id)
      end
    end
  end

  def parse_faculty_name(display_name)
    return [nil, nil] if display_name.blank?

    # Handle "Last, First" or "Last, First Middle" format
    if display_name.include?(",")
      parts = display_name.split(",").map(&:strip)
      last_name = parts[0]
      # For "Last, First Middle", take only the first word as first name
      first_name_parts = parts[1]&.split(/\s+/) || []
      first_name = first_name_parts[0]
      [first_name, last_name]
    # Handle "First Last" or "First Middle Last" format
    else
      parts = display_name.split(/\s+/)
      if parts.length >= 2
        # First word is first name, last word is last name (ignoring middle names)
        [parts[0], parts[-1]]
      else
        # Single name - use for both first and last
        [display_name, display_name]
      end
    end
  end

  # Parse date from MM/DD/YYYY format (e.g., "01/06/2026")
  def parse_date(date_string)
    return nil if date_string.blank?

    begin
      Date.strptime(date_string, "%m/%d/%Y")
    rescue ArgumentError => e
      Rails.logger.warn("Failed to parse date '#{date_string}': #{e.message}")
      nil
    end
  end

  # Validate that dates are reasonable for the term year
  # LeopardWeb sometimes returns stale/historical dates from previous years
  def dates_valid_for_term?(start_date, end_date, term)
    return false if start_date.nil? || end_date.nil?

    term_year = term.year

    # Allow dates within 1 year of the term year (for fall terms that span years)
    start_year_valid = start_date.year >= (term_year - 1) && start_date.year <= term_year
    end_year_valid = end_date.year >= term_year && end_date.year <= (term_year + 1)

    start_year_valid && end_year_valid
  end
end
