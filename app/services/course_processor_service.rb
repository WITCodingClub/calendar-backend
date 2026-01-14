# frozen_string_literal: true

class CourseProcessorService < ApplicationService
  include ApplicationHelper

  attr_reader :courses, :user

  def initialize(courses, user)
    @courses = courses
    @user = user
    super()
  end

  def call
    # Validate input
    validate_courses_data!

    processed_courses = []

    # Group courses by CRN and term to handle multiple meeting times per course
    grouped_courses = courses.group_by { |c| [c[:crn], c[:term]] }

    grouped_courses.each_value do |course_meetings|
      # Use the first meeting for course details (they should all be the same course)
      course_data = course_meetings.first
      detailed_course_info = LeopardWebService.get_class_details(
        term: course_data[:term],
        course_reference_number: course_data[:crn]
      )

      # Look up term by UID - it should already exist via EnsureFutureTermsJob
      term = Term.find_by(uid: course_data[:term])

      unless term
        raise InvalidTermError.new(
          course_data[:term],
          "Term with UID #{course_data[:term]} not found. Please ensure EnsureFutureTermsJob has run."
        )
      end

      # schedule_type: "Lecture (LEC)",
      # parse schedule type to get code in parentheses
      schedule_type_match = detailed_course_info[:schedule_type].to_s.match(/\(([^)]+)\)/)


      # Convert frontend meeting time format to the expected format
      # Group meetings by time to handle courses that meet multiple days per week
      time_groups = course_meetings.group_by do |meeting|
        start_value = meeting[:start] || meeting["start"]
        end_value = meeting[:end] || meeting["end"]

        # Handle both datetime strings and Date objects
        start_time = start_value.is_a?(String) ? Time.zone.parse(start_value) : start_value.to_time
        end_time = end_value.is_a?(String) ? Time.zone.parse(end_value) : end_value.to_time

        [start_time.strftime("%H:%M"), end_time.strftime("%H:%M")]
      end

      meeting_times = time_groups.map do |time_key, meetings|
        # Collect all days this time slot occurs
        days = {
          "sunday"    => false,
          "monday"    => false,
          "tuesday"   => false,
          "wednesday" => false,
          "thursday"  => false,
          "friday"    => false,
          "saturday"  => false
        }

        start_dates = []
        end_dates = []

        meetings.each do |meeting|
          start_value = meeting[:start] || meeting["start"]
          end_value = meeting[:end] || meeting["end"]

          # Handle both datetime strings and Date objects
          start_time = start_value.is_a?(String) ? Time.zone.parse(start_value) : start_value.to_time
          end_time = end_value.is_a?(String) ? Time.zone.parse(end_value) : end_value.to_time

          day_of_week = start_time.wday
          day_names = %w[sunday monday tuesday wednesday thursday friday saturday]
          days[day_names[day_of_week]] = true

          start_dates << start_time.strftime("%m/%d/%Y")
          end_dates << end_time.strftime("%m/%d/%Y")
        end

        # Use the earliest start date and latest end date
        start_date = start_dates.min
        end_date = end_dates.max
        begin_time, end_time = time_key

        {
          "startDate"           => start_date,
          "endDate"             => end_date,
          "beginTime"           => begin_time,
          "endTime"             => end_time,
          # Extract location info from first meeting if available, fallback to TBD
          "building"            => meetings.first[:building] || meetings.first["building"] || "TBD",
          "buildingDescription" => meetings.first[:buildingDescription] || meetings.first["buildingDescription"] || "To Be Determined",
          "room"                => meetings.first[:room] || meetings.first["room"] || "TBD"
        }.merge(days)
      end

      # Extract faculty data from the first meeting time
      faculty_data = []
      first_meeting = course_meetings.first
      if first_meeting[:instructor] || first_meeting["instructor"] || first_meeting[:faculty] || first_meeting["faculty"]
        instructor_name = first_meeting[:instructor] || first_meeting["instructor"] || first_meeting[:faculty] || first_meeting["faculty"]
        instructor_email = first_meeting[:instructorEmail] || first_meeting["instructorEmail"] || first_meeting[:facultyEmail] || first_meeting["facultyEmail"]

        if instructor_name.present? && instructor_name.to_s.strip != ""
          faculty_data = [{
            displayName: instructor_name.to_s.strip,
            emailAddress: instructor_email.to_s.strip.presence || "#{instructor_name.to_s.strip.downcase.gsub(/\s+/, '.')}@wit.edu"
          }]
        end
      end

      # Get course start/end dates from first meeting time (in MM/DD/YYYY format)
      start_date = nil
      end_date = nil
      if meeting_times.any?
        first_meeting = meeting_times.first
        start_date = parse_date(first_meeting["startDate"])
        end_date = parse_date(first_meeting["endDate"])
      end

      course = Course.find_or_create_by!(crn: course_data[:crn], term: term) do |c|
        c.title = titleize_with_roman_numerals(detailed_course_info[:title])
        c.start_date = start_date
        c.end_date = end_date
        c.subject = detailed_course_info[:subject]
        c.course_number = course_data[:courseNumber]
        c.schedule_type = schedule_type_match ? schedule_type_match[1] : nil
        c.section_number = normalize_section_number(detailed_course_info[:section_number])

        # LeopardWeb shows total course credit hours for all sections (lecture + lab)
        # Labs are typically 0-credit companion sections, so override for LAB schedule type
        c.credit_hours = schedule_type_match && schedule_type_match[1] == "LAB" ? 0 : detailed_course_info[:credit_hours]
        c.grade_mode = detailed_course_info[:grade_mode]
      end

      # Update course if it already exists (title may have changed or need re-titleization)
      if course.persisted? && !course.new_record?
        update_attrs = {}
        update_attrs[:start_date] = start_date if start_date.present?
        update_attrs[:end_date] = end_date if end_date.present?

        # Always re-apply titleization to ensure consistent formatting
        if detailed_course_info[:title].present?
          new_title = titleize_with_roman_numerals(detailed_course_info[:title])
          update_attrs[:title] = new_title if course.title != new_title
        end

        course.update!(update_attrs) if update_attrs.any?
      end

      # Link orphan FinalExam records to this course (if finals schedule was uploaded before courses)
      orphan_exam = FinalExam.orphan.find_by(crn: course.crn, term: term)
      if orphan_exam
        orphan_exam.update!(course: course)
        Rails.logger.info("Linked FinalExam for CRN #{course.crn} to course #{course.id}")
      end

      MeetingTimesIngestService.call(
        course: course,
        raw_meeting_times: meeting_times
      )

      # Process and associate faculty with the course
      process_faculty(course, faculty_data)

      enrollment = Enrollment.find_or_create_by!(user: user, course: course, term: term)

      # Reload course to get associated meeting times with their associations
      course = Course.includes(:faculties, meeting_times: [:building, :room]).find(course.id)

      # Collect processed course data
      processed_courses << {
        id: course.id,
        title: course.title,
        crn: course.crn,
        subject: course.subject,
        course_number: course.course_number,
        schedule_type: course.schedule_type,
        instructors: course.faculties.map do |faculty|
          {
            name: faculty.display_name,
            first_name: faculty.first_name,
            last_name: faculty.last_name,
            email: faculty.email
          }
        end,
        term: {
          uid: term.uid,
          season: term.season,
          year: term.year
        },
        meeting_times: course.meeting_times.map do |mt|
          {
            begin_time: mt.fmt_begin_time,
            end_time: mt.fmt_end_time,
            start_date: mt.start_date,
            end_date: mt.end_date,
            day_of_week: mt.day_of_week,
            location: {
              building: if mt.building
                          {
                            name: mt.building.name,
                            abbreviation: mt.building.abbreviation
                          }
                        else
                          nil
                        end,
              room: mt.room&.formatted_number
            }
          }
        end
      }
    end

    # Trigger immediate calendar sync if user has Google Calendar configured
    if user.google_course_calendar_id.present?
      GoogleCalendarSyncJob.perform_later(user, force: false)
    end

    processed_courses
  end

  private

  def validate_courses_data!
    raise ArgumentError, "courses cannot be nil" if courses.nil?
    raise ArgumentError, "courses must be an array" unless courses.is_a?(Array)
    raise ArgumentError, "courses cannot be empty" if courses.empty?

    courses.each_with_index do |course_data, index|
      unless course_data.is_a?(Hash)
        raise ArgumentError, "course at index #{index} must be a hash"
      end

      if course_data[:crn].blank?
        raise ArgumentError, "course at index #{index} missing required field: crn"
      end

      if course_data[:term].blank?
        raise ArgumentError, "course at index #{index} missing required field: term"
      end

      # Validate term UID is numeric
      unless course_data[:term].to_s.match?(/^\d+$/)
        raise ArgumentError, "course at index #{index} has invalid term UID: #{course_data[:term]}"
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

      # Associate with course (use Set for O(1) lookup instead of loading all faculties)
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

end
