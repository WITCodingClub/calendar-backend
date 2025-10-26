class CourseEventsProcessorService < ApplicationService
  attr_reader :events, :user

  def initialize(events, user)
    @events = events
    @user = user
    super()
  end

  def call
    # Extract unique term/CRN combinations
    unique_courses = extract_unique_courses

    # Process each unique course
    unique_courses.each do |course_info|
      process_course(course_info[:term], course_info[:crn])
    end

    { processed: unique_courses.count }
  end

  private

  def extract_unique_courses
    courses = events.map do |event|
      {
        term: event["term"] || event[:term],
        crn: event["crn"] || event[:crn]
      }
    end

    courses.uniq
  end

  def process_course(term_code, crn)
    # Parse term code (e.g., "202610" -> year: 2026, semester: 1)
    term = find_or_create_term(term_code)

    # Get class details from Leopard
    class_details = LeopardWebService.get_class_details(
      term: term_code,
      course_reference_number: crn
    )

    return unless class_details

    # Create or update academic class
    academic_class = find_or_create_academic_class(term, crn, class_details)

    # Get faculty and meeting times
    faculty_meeting_data = LeopardWebService.get_faculty_meeting_times(
      term: term_code,
      course_reference_number: crn
    )

    # Process faculty and meeting times if available
    process_faculty_and_meetings(academic_class, faculty_meeting_data) if faculty_meeting_data

    # Create enrollment for the user
    create_enrollment(user, academic_class, term)

    academic_class
  rescue StandardError => e
    Rails.logger.error("Error processing course #{crn} for term #{term_code}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    nil
  end

  def find_or_create_term(term_code)
    # Parse term code: first 4 digits = year, last 2 digits = semester
    # 10 = Spring (1), 20 = Summer (3), 30 = Fall (2)
    year = term_code[0..3].to_i
    semester_code = term_code[4..5].to_i

    semester = case semester_code
               when 10 then 1  # Spring
               when 20 then 3  # Summer
               when 30 then 2  # Fall
               else 1  # Default to Spring
               end

    Term.find_or_create_by!(year: year, semester: semester) do |term|
      term.uid = term_code
    end
  end

  def find_or_create_academic_class(term, crn, class_details)
    AcademicClass.find_or_initialize_by(term: term, crn: crn).tap do |academic_class|
      academic_class.assign_attributes(
        course_number: class_details[:course_number]&.to_i,
        subject: class_details[:subject],
        title: class_details[:title],
        section_number: class_details[:section_number],
        credit_hours: class_details[:credit_hours],
        grade_mode: class_details[:grade_mode],
        schedule_type: map_schedule_type(class_details[:schedule_type])
      )
      academic_class.save!
    end
  end

  def map_schedule_type(schedule_type_string)
    # Map the string from Leopard to the enum value
    return "lecture" unless schedule_type_string

    case schedule_type_string.downcase
    when /hybrid/ then "hybrid"
    when /lab/ then "laboratory"
    when /lecture/ then "lecture"
    when /online.*lab/ then "online_sync_lab"
    when /online.*lec/ then "online_sync_lecture"
    when /rotating.*lab/ then "rotating_lab"
    when /rotating.*lec/ then "rotating_lecture"
    else "lecture"  # Default
    end
  end

  def process_faculty_and_meetings(academic_class, faculty_meeting_data)
    # Process faculty if present
    if faculty_meeting_data.is_a?(Hash) && faculty_meeting_data["faculty"]
      process_faculty(academic_class, faculty_meeting_data["faculty"])
    end

    # Process meeting times if present
    if faculty_meeting_data.is_a?(Hash) && faculty_meeting_data["meetingTimes"]
      process_meeting_times(academic_class, faculty_meeting_data["meetingTimes"])
    end
  end

  def process_faculty(academic_class, faculty_data)
    return unless faculty_data.is_a?(Array)

    faculty_data.each do |faculty_info|
      faculty = Faculty.find_or_create_by(email: faculty_info["email"]) do |f|
        f.first_name = faculty_info["firstName"] || faculty_info["first_name"] || ""
        f.last_name = faculty_info["lastName"] || faculty_info["last_name"] || ""
      end

      academic_class.faculties << faculty unless academic_class.faculties.include?(faculty)
    end
  end

  def process_meeting_times(academic_class, meeting_times_data)
    return unless meeting_times_data.is_a?(Array)

    meeting_times_data.each do |meeting_info|
      # Find or create building and room
      building = find_or_create_building(meeting_info)
      room = find_or_create_room(building, meeting_info)

      # Create meeting time
      MeetingTime.find_or_create_by(
        academic_class: academic_class,
        room: room,
        begin_time: meeting_info["beginTime"]&.to_i || 0,
        end_time: meeting_info["endTime"]&.to_i || 0
      ) do |mt|
        mt.start_date = parse_date(meeting_info["startDate"])
        mt.end_date = parse_date(meeting_info["endDate"])
        mt.monday = meeting_info["monday"] || false
        mt.tuesday = meeting_info["tuesday"] || false
        mt.wednesday = meeting_info["wednesday"] || false
        mt.thursday = meeting_info["thursday"] || false
        mt.friday = meeting_info["friday"] || false
        mt.saturday = meeting_info["saturday"] || false
        mt.sunday = meeting_info["sunday"] || false
        mt.hours_week = meeting_info["hoursWeek"]&.to_i
        mt.meeting_schedule_type = meeting_info["meetingScheduleType"]&.to_i
        mt.meeting_type = meeting_info["meetingType"]&.to_i
      end
    end
  end

  def find_or_create_building(meeting_info)
    building_name = meeting_info["building"] || meeting_info["buildingDescription"] || "Unknown"
    building_abbr = meeting_info["buildingAbbreviation"] || building_name[0..2].upcase

    Building.find_or_create_by(abbreviation: building_abbr) do |b|
      b.name = building_name
    end
  end

  def find_or_create_room(building, meeting_info)
    room_number = meeting_info["room"] || meeting_info["roomNumber"] || 0

    Room.find_or_create_by(building: building, number: room_number.to_i)
  end

  def parse_date(date_string)
    return Time.current unless date_string

    # Handle different date formats
    Date.parse(date_string)
  rescue ArgumentError
    Time.current
  end

  def create_enrollment(user, academic_class, term)
    # Create or find enrollment for user in this class and term
    Enrollment.find_or_create_by!(
      user: user,
      academic_class: academic_class,
      term: term
    )
  rescue StandardError => e
    Rails.logger.error("Error creating enrollment for user #{user.id}, class #{academic_class.id}: #{e.message}")
    nil
  end
end
