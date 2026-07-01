# frozen_string_literal: true

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

    unique_courses = catalog_courses.uniq { |c| [ c["courseReferenceNumber"], c["term"] ] }

    term_uids = unique_courses.map { |c| c["term"] || c["termEffective"] }.compact.uniq

    missing = term_uids.reject { |uid| Term.exists?(uid: uid) }
    if missing.any?
      raise ArgumentError, "Terms not found in database: #{missing.join(', ')}. Create them before importing."
    end

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

      if (index + 1) % 50 == 0
        Rails.logger.info("Processed #{index + 1}/#{unique_courses.count} courses")
      end
    end

    term_uids.each do |term_uid|
      term = Term.find_by(uid: term_uid)
      next unless term && processed_count > 0

      term.update!(
        catalog_imported: true,
        catalog_imported_at: Time.current
      )
      Rails.logger.info("Marked term #{term_uid} (#{term.name}) as catalog_imported")
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
    crn = course_data["courseReferenceNumber"] || course_data["crn"]
    term_uid = course_data["term"] || course_data["termEffective"]

    term = Term.find_by(uid: term_uid)
    unless term
      raise "Term with UID #{term_uid} not found. Please create the term first."
    end

    schedule_type_desc = course_data["scheduleTypeDescription"] || course_data["scheduleType"]
    schedule_type_match = schedule_type_desc.to_s.match(/\(([^)]+)\)/)
    raw_code = schedule_type_match ? schedule_type_match[1] : nil
    schedule_type_key = raw_code ? Course::ScheduleType.key_for_code(raw_code) : nil

    raise "Unknown or missing schedule type '#{schedule_type_desc}' (extracted code: #{raw_code.inspect}) for CRN #{crn}" unless schedule_type_key

    raw_meeting_times = []
    if course_data["meetingsFaculty"].is_a?(Array)
      course_data["meetingsFaculty"].each do |session|
        meeting_time = session["meetingTime"]
        raw_meeting_times << meeting_time if meeting_time.present?
      end
    end

    meeting_times = deduplicate_meeting_times(raw_meeting_times)

    start_date = nil
    end_date = nil
    if meeting_times.any?
      first_meeting = meeting_times.first
      parsed_start = parse_date(first_meeting["startDate"])
      parsed_end = parse_date(first_meeting["endDate"])

      if dates_valid_for_term?(parsed_start, parsed_end, term)
        start_date = parsed_start
        end_date = parsed_end
      else
        Rails.logger.warn("Invalid dates for term #{term.name}: #{parsed_start} to #{parsed_end}, using term defaults")
        start_date = term.start_date
        end_date = term.end_date
      end
    else
      start_date = term.start_date
      end_date = term.end_date
    end

    if start_date.nil? || end_date.nil?
      raise "Cannot determine dates for CRN #{crn}: no meeting times and term #{term.uid} (#{term.name}) has no dates set"
    end

    course = Course.find_or_create_by!(crn: crn, term: term) do |c|
      c.title = titleize_with_roman_numerals(course_data["courseTitle"] || "Untitled Course")
      c.subject = course_data["subject"] || course_data["subjectCode"]
      c.course_number = course_data["courseNumber"]
      c.schedule_type = schedule_type_key
      c.section_number = normalize_section_number(course_data["sequenceNumber"] || course_data["sectionNumber"])
      raw_hours = raw_code == "LAB" ? nil : course_data["creditHours"]
      c.credit_hours = raw_hours.to_i.positive? ? raw_hours : nil
      c.grade_mode = nil
      c.start_date = start_date
      c.end_date = end_date
      c.term = term
    end

    if course.persisted? && !course.new_record?
      update_attrs = {}
      update_attrs[:start_date] = start_date if start_date.present?
      update_attrs[:end_date] = end_date if end_date.present?

      raw_title = course_data["courseTitle"] || "Untitled Course"
      new_title = titleize_with_roman_numerals(raw_title)
      update_attrs[:title] = new_title if course.title != new_title

      course.update!(update_attrs) if update_attrs.any?
    end

    orphan_exam = FinalExam.orphan.find_by(crn: course.crn, term: term)
    if orphan_exam
      orphan_exam.update!(course: course)
      Rails.logger.info("Linked FinalExam for CRN #{course.crn} to course #{course.id}")
    end

    if meeting_times.any?
      kept_ids = MeetingTimesIngestService.call(
        course: course,
        raw_meeting_times: meeting_times
      )

      # Remove meeting times that no longer exist upstream (e.g. Banner changed a
      # section's day/time), but only when the ingest produced rows — never wipe
      # the course from an empty result. Preserves untouched rows and their events.
      course.meeting_times.where.not(id: kept_ids).destroy_all if kept_ids.any?
    else
      Rails.logger.warn("No meeting times found for course CRN #{crn}")
    end

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

      crn = course_data["courseReferenceNumber"] || course_data["crn"]
      if crn.blank?
        available_keys = course_data.keys.first(15).join(", ")
        raise ArgumentError, "course at index #{index} missing required field: courseReferenceNumber or crn. Available keys: #{available_keys}"
      end

      term_uid = course_data["term"] || course_data["termEffective"]
      if term_uid.blank?
        raise ArgumentError, "course at index #{index} missing required field: term or termEffective"
      end

      unless term_uid.to_s.match?(/^\d+$/)
        raise ArgumentError, "course at index #{index} has invalid term UID: #{term_uid}"
      end
    end
  end

  def process_faculty(course, faculty_data)
    unique_faculty = faculty_data.uniq { |f| f["emailAddress"] || f[:emailAddress] }
    existing_faculty_ids = course.faculty_ids.to_set

    unique_faculty.each do |faculty_info|
      next if faculty_info.blank?

      email = (faculty_info["emailAddress"] || faculty_info[:emailAddress]).to_s.strip
      display_name = (faculty_info["displayName"] || faculty_info[:displayName]).to_s.strip

      next if email.blank?

      first_name, last_name = parse_faculty_name(display_name)
      next if first_name.blank? || last_name.blank?

      faculty = Faculty.find_or_create_by!(email: email) do |f|
        f.first_name = first_name
        f.last_name = last_name
      end

      unless existing_faculty_ids.include?(faculty.id)
        course.faculties << faculty
        existing_faculty_ids.add(faculty.id)
      end
    end
  end

  def parse_faculty_name(display_name)
    return [ nil, nil ] if display_name.blank?

    if display_name.include?(",")
      parts = display_name.split(",").map(&:strip)
      last_name = parts[0]
      first_name_parts = parts[1]&.split(/\s+/) || []
      first_name = first_name_parts[0]
      [ first_name, last_name ]
    else
      parts = display_name.split(/\s+/)
      if parts.length >= 2
        [ parts[0], parts[-1] ]
      else
        [ display_name, display_name ]
      end
    end
  end

  def parse_date(date_string)
    return nil if date_string.blank?

    Date.strptime(date_string, "%m/%d/%Y")
  rescue ArgumentError => e
    Rails.logger.warn("Failed to parse date '#{date_string}': #{e.message}")
    nil
  end

  def dates_valid_for_term?(start_date, end_date, term)
    return false if start_date.nil? || end_date.nil?

    term_year = term.year
    start_year_valid = start_date.year.between?(term_year - 1, term_year)
    end_year_valid = end_date.year.between?(term_year, term_year + 1)

    start_year_valid && end_year_valid
  end

  def deduplicate_meeting_times(raw_meeting_times)
    return [] if raw_meeting_times.blank?

    grouped = raw_meeting_times.group_by { |mt| meeting_time_schedule_key(mt) }

    grouped.map do |_key, entries|
      next entries.first if entries.size == 1

      with_location = entries.find { |mt| meeting_time_has_location?(mt) }
      with_location || entries.first
    end
  end

  def meeting_time_schedule_key(mt)
    days = %w[sunday monday tuesday wednesday thursday friday saturday].map do |day|
      mt[day] || mt[day.to_sym] ? 1 : 0
    end.join

    [
      mt["startDate"] || mt[:startDate],
      mt["endDate"] || mt[:endDate],
      mt["beginTime"] || mt[:beginTime],
      mt["endTime"] || mt[:endTime],
      days
    ]
  end

  def meeting_time_has_location?(mt)
    building = (mt["building"] || mt[:building]).to_s.strip
    room = (mt["room"] || mt[:room]).to_s.strip

    return false if building.blank?
    return false if building.downcase == "tbd"

    if room.present?
      return false if room == "0"
      return false if room.downcase == "tbd"
    end

    true
  end
end
