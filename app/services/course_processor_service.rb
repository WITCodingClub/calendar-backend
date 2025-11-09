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

      course = Course.find_or_create_by!(crn: course_data[:crn]) do |c|
        c.title = titleize_with_roman_numerals(detailed_course_info[:title])
        c.start_date = course_data[:start]
        c.end_date = course_data[:end]
        c.subject = detailed_course_info[:subject]
        c.course_number = course_data[:courseNumber]
        c.schedule_type = schedule_type_match ? schedule_type_match[1] : nil
        c.section_number = detailed_course_info[:section_number]
        c.credit_hours = detailed_course_info[:credit_hours]
        c.grade_mode = detailed_course_info[:grade_mode]

        c.term = term
      end

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

      MeetingTimesIngestService.call(
        course: course,
        raw_meeting_times: meeting_times
      )

      # Process and associate faculty with the course
      process_faculty(course, faculty_data)

      Enrollment.find_or_create_by!(user: user, course: course, term: term)

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

end
