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
    validate_courses_data!

    processed_courses = []

    grouped_courses = courses.group_by { |c| [c[:crn], c[:term]] }

    term_uids = grouped_courses.keys.map { |_, term_uid| term_uid }.uniq
    term_cache = Term.where(uid: term_uids).index_by { |t| t.uid.to_s }

    crns = grouped_courses.keys.map { |crn, _| crn }
    term_ids = term_cache.values.map(&:id)
    course_cache = Course.where(crn: crns, term_id: term_ids).index_by { |c| [c.crn.to_s, c.term_id] }

    orphan_exam_cache = FinalExam.orphan.where(crn: crns, term_id: term_ids)
                                 .index_by { |e| [e.crn.to_s, e.term_id] }

    Term.with_deferred_date_updates do
      grouped_courses.each_value do |course_meetings|
        course_data = course_meetings.first
        detailed_course_info = LeopardWebService.get_class_details(
          term: course_data[:term],
          course_reference_number: course_data[:crn]
        )

        term = term_cache[course_data[:term].to_s]

        unless term
          raise InvalidTermError.new(
            course_data[:term],
            "Term with UID #{course_data[:term]} not found. Please ensure EnsureFutureTermsJob has run."
          )
        end

        schedule_type_match = detailed_course_info[:schedule_type].to_s.match(/\(([^)]+)\)/)

        time_groups = course_meetings.group_by do |meeting|
          start_value = meeting[:start] || meeting["start"]
          end_value = meeting[:end] || meeting["end"]

          start_time = start_value.is_a?(String) ? Time.zone.parse(start_value) : start_value.to_time
          end_time = end_value.is_a?(String) ? Time.zone.parse(end_value) : end_value.to_time

          [start_time.strftime("%H:%M"), end_time.strftime("%H:%M")]
        end

        meeting_times = time_groups.map do |time_key, meetings|
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

            start_time = start_value.is_a?(String) ? Time.zone.parse(start_value) : start_value.to_time
            end_time = end_value.is_a?(String) ? Time.zone.parse(end_value) : end_value.to_time

            day_of_week = start_time.wday
            day_names = %w[sunday monday tuesday wednesday thursday friday saturday]
            days[day_names[day_of_week]] = true

            start_dates << start_time.strftime("%m/%d/%Y")
            end_dates << end_time.strftime("%m/%d/%Y")
          end

          start_date = start_dates.min
          end_date = end_dates.max
          begin_time, end_time = time_key

          {
            "startDate"           => start_date,
            "endDate"             => end_date,
            "beginTime"           => begin_time,
            "endTime"             => end_time,
            "building"            => meetings.first[:building] || meetings.first["building"] || "TBD",
            "buildingDescription" => meetings.first[:buildingDescription] || meetings.first["buildingDescription"] || "To Be Determined",
            "room"                => meetings.first[:room] || meetings.first["room"] || "TBD"
          }.merge(days)
        end

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

        start_date = nil
        end_date = nil
        if meeting_times.any?
          first_mt = meeting_times.first
          start_date = parse_date(first_mt["startDate"])
          end_date = parse_date(first_mt["endDate"])
        end

        course = course_cache[[course_data[:crn].to_s, term.id]]
        if course.nil?
          course = Course.new(crn: course_data[:crn], term: term)
          course.title          = titleize_with_roman_numerals(detailed_course_info[:title])
          course.start_date     = start_date
          course.end_date       = end_date
          course.subject        = detailed_course_info[:subject]
          course.course_number  = course_data[:courseNumber]
          course.schedule_type  = schedule_type_match ? schedule_type_match[1] : nil
          course.section_number = normalize_section_number(detailed_course_info[:section_number])
          course.credit_hours   = schedule_type_match && schedule_type_match[1] == "LAB" ? 0 : detailed_course_info[:credit_hours]
          course.grade_mode     = detailed_course_info[:grade_mode]
          course.seats_available = detailed_course_info[:seats_available]
          course.seats_capacity  = detailed_course_info[:seats_capacity]
          course.save!
        end

        if course.persisted? && !course.new_record?
          update_attrs = {}
          update_attrs[:start_date] = start_date if start_date.present?
          update_attrs[:end_date] = end_date if end_date.present?

          if detailed_course_info[:title].present?
            new_title = titleize_with_roman_numerals(detailed_course_info[:title])
            update_attrs[:title] = new_title if course.title != new_title
          end

          update_attrs[:seats_available] = detailed_course_info[:seats_available] unless detailed_course_info[:seats_available].nil?
          update_attrs[:seats_capacity]  = detailed_course_info[:seats_capacity]  unless detailed_course_info[:seats_capacity].nil?

          course.update!(update_attrs) if update_attrs.any?
        end

        orphan_exam = orphan_exam_cache[[course.crn.to_s, term.id]]
        if orphan_exam
          orphan_exam.update!(course: course)
          Rails.logger.info("Linked FinalExam for CRN #{course.crn} to course #{course.id}")
        end

        MeetingTimesIngestService.call(
          course: course,
          raw_meeting_times: meeting_times
        )

        process_faculty(course, faculty_data)

        Enrollment.find_or_create_by!(user: user, course: course, term: term)

        course = Course.includes(:faculties, meeting_times: [:room]).find(course.id)

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
                building: if mt.room&.building
                              {
                                name: mt.room.building.name,
                                abbreviation: mt.room.building.abbreviation
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
    end

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

      unless course_data[:term].to_s.match?(/^\d+$/)
        raise ArgumentError, "course at index #{index} has invalid term UID: #{course_data[:term]}"
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
    return [nil, nil] if display_name.blank?

    if display_name.include?(",")
      parts = display_name.split(",").map(&:strip)
      last_name = parts[0]
      first_name_parts = parts[1]&.split(/\s+/) || []
      first_name = first_name_parts[0]
      [first_name, last_name]
    else
      parts = display_name.split(/\s+/)
      if parts.length >= 2
        [parts[0], parts[-1]]
      else
        [display_name, display_name]
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
end
