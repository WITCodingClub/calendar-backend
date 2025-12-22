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

    # Deduplicate courses by CRN and term
    unique_courses = courses.uniq { |c| [c[:crn], c[:term]] }

    # Track courses to be processed
    StatsD.gauge("course.processor.courses_count", unique_courses.count, tags: ["user_id:#{user.id}"])

    unique_courses.each do |course_data|
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


      detailed_meeting_times = LeopardWebService.get_faculty_meeting_times(
        term: course_data[:term],
        course_reference_number: course_data[:crn]
      )

      # Extract meeting times and faculty from nested structure
      meeting_times = []
      faculty_data = []
      if detailed_meeting_times["fmt"].is_a?(Array)
        detailed_meeting_times["fmt"].each do |session|
          meeting_time = session["meetingTime"]
          meeting_times << meeting_time if meeting_time

          # Extract faculty information (faculty is an array)
          faculty = session["faculty"]
          if faculty.present? && faculty.is_a?(Array)
            faculty_data.concat(faculty)
          elsif faculty.present?
            faculty_data << faculty
          end
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

      course = Course.find_or_create_by!(crn: course_data[:crn]) do |c|
        c.title = titleize_with_roman_numerals(detailed_course_info[:title])
        c.start_date = start_date
        c.end_date = end_date
        c.subject = detailed_course_info[:subject]
        c.course_number = course_data[:courseNumber]
        c.schedule_type = schedule_type_match ? schedule_type_match[1] : nil
        c.section_number = detailed_course_info[:section_number]

        # LeopardWeb shows total course credit hours for all sections (lecture + lab)
        # Labs are typically 0-credit companion sections, so override for LAB schedule type
        c.credit_hours = (schedule_type_match && schedule_type_match[1] == "LAB") ? 0 : detailed_course_info[:credit_hours]
        c.grade_mode = detailed_course_info[:grade_mode]

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

      MeetingTimesIngestService.call(
        course: course,
        raw_meeting_times: meeting_times
      )

      # Process and associate faculty with the course
      process_faculty(course, faculty_data)

      enrollment = Enrollment.find_or_create_by!(user: user, course: course, term: term)

      # Track enrollment creation
      StatsD.increment("course.processor.enrollment_created", tags: ["user_id:#{user.id}", "course_id:#{course.id}"])

      # Reload course to get associated meeting times with their associations
      course = Course.includes(meeting_times: [:building, :room]).find(course.id)

      # Collect processed course data
      processed_courses << {
        id: course.id,
        title: course.title,
        course_number: course.course_number,
        schedule_type: course.schedule_type,
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

    # Track faculty count
    StatsD.gauge("course.processor.faculty_count", unique_faculty.count, tags: ["course_id:#{course.id}"])

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

        # Track faculty association
        StatsD.increment("course.processor.faculty_associated", tags: ["course_id:#{course.id}", "faculty_id:#{faculty.id}"])
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
