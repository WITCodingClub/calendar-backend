class CourseProcessorService < ApplicationService
  include ApplicationHelper

  attr_reader :courses, :user

  def initialize(courses, user)
    @courses = courses
    @user = user
    super()
  end

  def call
    processed_courses = []

    # Deduplicate courses by CRN and term
    unique_courses = courses.uniq { |c| [c[:crn], c[:term]] }

    unique_courses.each do |course_data|
      detailed_course_info = LeopardWebService.get_class_details(
        term: course_data[:term],
        course_reference_number: course_data[:crn]
      )

      term = Term.find_or_create_by!(uid: course_data[:term]) do |t|
        associated_term = detailed_course_info[:associated_term]

        #   associated term is in format "Fall 2025"
        season_str, year_str = associated_term.to_s.strip.split(/\s+/)
        year = year_str.to_i
        season = case season_str
        when "Spring"
          :spring
        when "Fall"
          :fall
        when "Summer"
          :summer
        else
          raise "Unknown season string: #{season_str.inspect}"
        end

        t.year = year
        t.season = Term.seasons[season]

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

      # Extract meeting times from nested structure
      meeting_times = []
      if detailed_meeting_times["fmt"].is_a?(Array)
        detailed_meeting_times["fmt"].each do |session|
          meeting_time = session["meetingTime"]
          meeting_times << meeting_time if meeting_time
        end
      end

      MeetingTimesIngestService.call(
        course: course,
        raw_meeting_times: meeting_times
      )

      Enrollment.find_or_create_by!(user: user, course: course, term: term)

      # Reload course to get associated meeting times
      course.reload

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
              building: mt.building ? {
                name: mt.building.name,
                abbreviation: mt.building.abbreviation
              } : nil,
              room: mt.room&.formatted_number
            }
          }
        end
      }
    end

    processed_courses
  end
end
