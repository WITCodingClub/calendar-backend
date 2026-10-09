# frozen_string_literal: true

module Courses
  class Processor < ApplicationService
    include ApplicationHelper

    attr_reader :courses, :user

    def initialize(courses, user)
      @courses = courses
      @user = user
      super()
    end

    def call
      validate_courses_data!

      processed = []
      touched_meeting_time_ids = []
      enrolled_terms = Set.new

      grouped_courses = courses.group_by { |c| [ c[:crn], c[:term] ] }

      term_uids = grouped_courses.keys.map { |_, term_uid| term_uid }.uniq
      term_cache = Term.where(uid: term_uids).index_by { |t| t.uid.to_s }

      crns = grouped_courses.keys.map { |crn, _| crn }
      term_ids = term_cache.values.map(&:id)
      course_cache = Course.where(crn: crns, term_id: term_ids).index_by { |c| [ c.crn.to_s, c.term_id ] }

      orphan_exam_cache = FinalExam.orphan.where(crn: crns, term_id: term_ids)
                                   .index_by { |e| [ e.crn.to_s, e.term_id ] }

      class_details = fetch_class_details(grouped_courses.keys)

      # Check every term before the first write. Enrollments and the removal of
      # old meeting times happen after the loop, so a raise inside it would leave
      # courses without an enrollment.
      grouped_courses.each_key do |crn_and_term|
        term_uid = crn_and_term.last
        next if class_details[crn_and_term].nil? || term_cache.key?(term_uid.to_s)

        raise Courses::InvalidTermError.new(
          term_uid,
          "Term with UID #{term_uid} not found. Please ensure Catalog::EnsureFutureTermsJob has run."
        )
      end

      # Load what the loop below reads for each course in one query each, so a
      # request with many courses does not send the same query for each (#723).
      meeting_times_by_key = grouped_courses.each_with_object({}) do |(key, course_meetings), acc|
        acc[key] = meeting_times_for(course_meetings, class_details[key]) if class_details[key]
      end

      existing_course_ids = course_cache.values.map(&:id)
      existing_meeting_times = Course::MeetingTime.where(course_id: existing_course_ids)
                                                  .includes(:meeting_time_rooms)
                                                  .group_by(&:course_id)
      existing_course_faculties = CourseFaculty.where(course_id: existing_course_ids).group_by(&:course_id)

      # Banner is the authority on who teaches a section. The posted schedule
      # is only a fallback for the rare section Banner answers with no
      # faculty, and only when it carries a real address: a guessed
      # first.last@wit.edu creates a second instructor who never matches the
      # real record.
      faculty_by_key = grouped_courses.each_with_object({}) do |(key, course_meetings), acc|
        acc[key] = class_details[key][:faculty].presence || posted_faculty(course_meetings.first) if class_details[key]
      end
      faculty = Faculties::Ingest.preload(faculty_by_key.values)

      # course_id => whether the course has any enrollment. Both change trackers
      # read it, so a save sends no EXISTS query.
      enrollment_flags = CourseCalendars::SyncMarker.enrollment_flags(existing_course_ids)

      Term.with_deferred_date_updates do
        locations = Catalog::MeetingTimesIngest::Locations.new
        locations.preload(meeting_times_by_key.values.flatten)

        CourseCalendars::SyncMarker.batch_with_enrollment_flags(enrollment_flags) do
          grouped_courses.each do |key, course_meetings|
            course_data = course_meetings.first
            detailed_course_info = class_details[key]

            unless detailed_course_info
              Rails.logger.warn("[Courses::Processor] No class details returned for CRN #{course_data[:crn]} in term #{course_data[:term]}, skipping")
              next
            end

            term = term_cache.fetch(course_data[:term].to_s)

            schedule_type_match = detailed_course_info[:schedule_type].to_s.match(/\(([^)]+)\)/)
            meeting_times = meeting_times_by_key[key]

            start_date = nil
            end_date = nil
            if meeting_times.any?
              first_mt = meeting_times.first
              start_date = parse_date(first_mt["startDate"])
              end_date = parse_date(first_mt["endDate"])
            end

            course = course_cache[[ course_data[:crn].to_s, term.id ]]
            if course.nil?
              course = Course.new(crn: course_data[:crn], term: term)
              course.title          = titleize_with_roman_numerals(detailed_course_info[:title])
              course.start_date     = start_date
              course.end_date       = end_date
              course.subject        = detailed_course_info[:subject]
              course.course_number  = course_data[:courseNumber]
              course.schedule_type  = schedule_type_match ? schedule_type_match[1] : nil
              course.section_number = normalize_section_number(detailed_course_info[:section_number])
              course.credit_hours   = schedule_type_match && schedule_type_match[1] == "LAB" ? nil : detailed_course_info[:credit_hours]
              course.grade_mode     = detailed_course_info[:grade_mode]
              course.seats_available = detailed_course_info[:seats_available]
              course.seats_capacity  = detailed_course_info[:seats_capacity]
              course.save!
              enrollment_flags[course.id] = false
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

            orphan_exam = orphan_exam_cache[[ course.crn.to_s, term.id ]]
            if orphan_exam
              orphan_exam.update!(course: course)
              Rails.logger.info("Linked FinalExam for CRN #{course.crn} to course #{course.id}")
            end

            # Upsert in place so meeting time IDs stay stable — destroying them
            # cascades to calendar_events tracking rows, which strands the
            # real events in Google Calendar and duplicates them on the next sync.
            # Only rows absent from the upload are removed, after the loop; their
            # calendar events are nullified and cleaned up by
            # CleanupOrphanedCalendarEventsJob.
            touched_meeting_time_ids.concat(
              Catalog::MeetingTimesIngest.call(
                course: course,
                raw_meeting_times: meeting_times,
                locations: locations,
                existing_meeting_times: existing_meeting_times.fetch(course.id, [])
              )
            )

            Faculties::Ingest.call(
              course: course,
              raw_faculty: faculty_by_key[key],
              faculty: faculty,
              existing_course_faculties: existing_course_faculties.fetch(course.id, [])
            )

            processed << [ course.id, term ]
            enrolled_terms << term
          end

          processed_course_ids = processed.map(&:first)
          Course::MeetingTime.where(course_id: processed_course_ids).where.not(id: touched_meeting_time_ids)
                           .includes(:meeting_time_rooms, :event_preference).destroy_all
        end
      end

      if processed.any?
        # The unique index on (user_id, course_id, term_id) skips enrollments
        # that already exist, so the uniqueness validation is not needed here.
        Enrollment.insert_all( # rubocop:disable Rails/SkipsModelValidations
          processed.map { |course_id, term| { user_id: user.id, course_id: course_id, term_id: term.id } },
          unique_by: :index_enrollments_on_user_class_term
        )
      end

      courses_by_id = Course.includes(:faculties, meeting_times: [ rooms: :building ])
                            .where(id: processed.map(&:first))
                            .index_by(&:id)
      processed_courses = processed.map do |course_id, term|
        course = courses_by_id.fetch(course_id)
        {
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
                rooms: mt.rooms.map(&:formatted_number)
              }
            }
          end
        }
      end

      # Mark a term processed only after all of its courses are done, so
      # /api/user/processed_events/status never reports a half-enrolled term.
      enrolled_terms.each { |term| TermProcessingStatus.record!(user, term, :processed) }

      if CourseCalendar.for_user(user).exists?
        CourseCalendars::SyncJob.perform_later(user, force: false)
      end

      processed_courses
    end

    # Checks the payload shape without calling Banner or writing anything.
    # Raises ArgumentError when the payload is not valid.
    def validate!
      validate_courses_data!
    end

    private

    # Banner answers one section per request, with two round trips each, and a
    # schedule has several sections. Asked one after another, process_courses
    # spent over a second waiting on Banner. The requests only use the network,
    # so send a few at once. An error in any request still raises here, before
    # anything is written.
    LEOPARD_WEB_CONCURRENCY = 6

    def fetch_class_details(keys)
      keys.each_slice(LEOPARD_WEB_CONCURRENCY).each_with_object({}) do |batch, details|
        threads = batch.map do |crn, term_uid|
          Thread.new do
            Thread.current.report_on_exception = false
            Rails.application.executor.wrap do
              Catalog::LeopardWebClient.get_class_details(term: term_uid, course_reference_number: crn)
            end
          end
        end

        ActiveSupport::Dependencies.interlock.permit_concurrent_loads do
          batch.zip(threads) { |key, thread| details[key] = thread.value }
        end
      end
    end

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

    # Prefer structured meeting times from getFacultyMeetingTimes — correct room/time data
    # with no timezone ambiguity. Fall back to parsing raw Banner calendar timestamps only
    # if structured data is unavailable.
    def meeting_times_for(course_meetings, detailed_course_info)
      if detailed_course_info[:meeting_times].present?
        Catalog::MeetingTimesIngest.normalize_leopard_web(detailed_course_info[:meeting_times])
      else
        time_groups = course_meetings.group_by do |meeting|
          start_value = meeting[:start] || meeting["start"]
          end_value = meeting[:end] || meeting["end"]

          start_time = start_value.is_a?(String) ? Time.zone.parse(start_value) : start_value.to_time
          end_time = end_value.is_a?(String) ? Time.zone.parse(end_value) : end_value.to_time

          [ start_time.strftime("%H:%M"), end_time.strftime("%H:%M") ]
        end

        time_groups.map do |time_key, meetings|
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
      end
    end


    def posted_faculty(meeting)
      return [] if meeting.blank?

      name  = meeting[:instructor] || meeting["instructor"] || meeting[:faculty] || meeting["faculty"]
      email = meeting[:instructorEmail] || meeting["instructorEmail"] || meeting[:facultyEmail] || meeting["facultyEmail"]

      return [] if name.blank? || email.blank?

      [ { "displayName" => name.to_s.strip, "emailAddress" => email.to_s.strip, "primaryIndicator" => true } ]
    end

    def parse_date(date_string)
      return nil if date_string.blank?

      Date.strptime(date_string, "%m/%d/%Y")
    rescue ArgumentError => e
      Rails.logger.warn("Failed to parse date '#{date_string}': #{e.message}")
      nil
    end
  end
end
