# frozen_string_literal: true

module CourseCalendars
  # Builds the event hashes that one person's calendar must hold: course
  # meetings, final exams, and university events. The provider services take
  # these hashes (see CourseCalendars::Providers).
  #
  # This class only reads the database. It does not call a provider.
  class EventBuilder
    attr_reader :user, :recurrence

    def initialize(user, recurrence: RecurrenceBuilder.new(user))
      @user       = user
      @recurrence = recurrence
    end

    # Loads the holidays of all the person's meeting times in one query, so the
    # EXDATE lines of each meeting time do not send a query each.
    def preload_holidays!
      recurrence.preload_holidays_for_user!
    end

    # The events of every meeting time of the given enrollments.
    # @param enrollment_scope [ActiveRecord::Relation<Enrollment>]
    # @param prefer_valid_locations [Boolean] when two meeting times have the
    #   same day and times, keep only one and prefer the one with a real location
    def course_events(enrollment_scope, prefer_valid_locations:)
      events = []

      enrollment_scope.includes(course: [ meeting_times: [ rooms: :building ] ]).find_each do |enrollment|
        course = enrollment.course
        meeting_times = prefer_valid_locations ? without_tbd_duplicates(course.meeting_times) : course.meeting_times

        meeting_times.each do |meeting_time|
          event = meeting_time_event(meeting_time, course)
          events << event if event
        end
      end

      events
    end

    # The event of one meeting time, or nil when the meeting time has no day,
    # no first meeting date, or no times.
    def meeting_time_event(meeting_time, course = meeting_time.course)
      # Skip if day_of_week is not set
      return nil if meeting_time.day_of_week.blank?

      # Find the first date this class actually meets
      first_meeting_date = recurrence.find_first_meeting_date(meeting_time)
      return nil unless first_meeting_date

      # Convert integer times (e.g., 900 = 9:00 AM) to DateTime objects
      start_time = recurrence.parse_time(first_meeting_date, meeting_time.begin_time)
      end_time = recurrence.parse_time(first_meeting_date, meeting_time.end_time)
      return nil unless start_time && end_time

      location = location_for(meeting_time)

      # Build course code from subject-number-section
      course_code = [ course.subject, course.course_number, course.section_number ].compact.join("-")

      # Build recurrence rule for weekly repeating events, with holiday exclusions
      recurrence_rule = recurrence.build_recurrence_rule(meeting_time)
      recurrence_lines = recurrence.build_recurrence_with_exclusions(meeting_time, recurrence_rule, start_time)

      {
        summary: course.title,
        description: course_code,
        location: location,
        start_time: start_time,
        end_time: end_time,
        course_code: course_code,
        meeting_time_id: meeting_time.id,
        recurrence: recurrence_lines,
        all_day: meeting_time.all_day?
      }
    end

    # The event of one final exam, or nil when the exam has no start or end.
    def final_exam_event(final_exam)
      return nil unless final_exam.start_datetime && final_exam.end_datetime

      {
        summary: "Final Exam: #{final_exam.course_title}",
        description: final_exam.course_code,
        location: final_exam.location_with_names,
        start_time: final_exam.start_datetime,
        end_time: final_exam.end_datetime,
        course_code: final_exam.course_code,
        final_exam_id: final_exam.id,
        recurrence: nil
      }
    end

    # Build events for final exams of enrolled courses.
    # time_scope: :future (default) — exams today or later (fast path)
    #             :past             — exams before today (historical backfill)
    #             :all              — no date filter
    def finals_events(time_scope: :future)
      finals = []

      enrolled_course_ids = user.enrollments.pluck(:course_id)
      return finals if enrolled_course_ids.empty?

      ::FinalExam.where(course_id: enrolled_course_ids)
                 .merge(final_exam_scope(time_scope))
                 .includes(course: :faculties)
                 .find_each do |final_exam|
                   event = final_exam_event(final_exam)
                   finals << event if event
      end

      finals
    end

    # Build university calendar events for sync.
    # time_scope: :future (default) — upcoming/current events only (fast path)
    #             :past             — events whose end_time is past (historical backfill)
    #             :all              — no date filter
    def university_events(time_scope: :future)
      events = []

      UniversityCalendarEvent.holidays.merge(university_event_scope(time_scope)).find_each do |event|
        events << {
          summary: event.formatted_holiday_summary,
          description: event.description,
          location: event.location,
          start_time: event.start_time,
          end_time: event.end_time,
          university_calendar_event_id: event.id,
          all_day: true,
          recurrence: nil
        }
      end

      user_config = user.user_extension_config
      if user_config&.sync_university_events
        categories = user_config.synced_university_event_categories
        unless categories.empty?
          UniversityCalendarEvent.by_categories(categories).merge(university_event_scope(time_scope)).find_each do |event|
            events << {
              summary: event.summary,
              description: event.description,
              location: event.location,
              start_time: event.start_time,
              end_time: event.end_time,
              university_calendar_event_id: event.id,
              all_day: event.all_day || false,
              recurrence: nil
            }
          end
        end
      end

      events
    end

    # The location text of a meeting time. TBD locations show "TBD".
    def location_for(meeting_time)
      non_tbd_rooms = meeting_time.rooms.reject { |r| tbd_room?(r) }
      if non_tbd_rooms.any? && meeting_time.building &&
         !tbd_building?(meeting_time.building)
        # Valid rooms and building
        "#{meeting_time.building.name} - #{non_tbd_rooms.map(&:formatted_number).join(' / ')}"
      elsif non_tbd_rooms.any?
        # Valid rooms, no building or invalid building
        non_tbd_rooms.map(&:formatted_number).join(" / ")
      elsif tbd_building?(meeting_time.building) || tbd_room?(meeting_time.room)
        # TBD location - show "TBD" instead of ugly "To Be Determined 000"
        "TBD"
      end
      # Else no location info: nil
    end

    # Check if this is a TBD/placeholder location that should be skipped
    def tbd_location?(building, room)
      tbd_building?(building) || tbd_room?(room)
    end

    # Check if building is TBD/placeholder
    # LeopardWeb sends null/empty for unassigned locations, not "TBD" placeholders
    def tbd_building?(building)
      return false unless building

      # Empty/blank building means location not yet assigned
      building.name.blank? ||
        building.abbreviation.blank? ||
        building.name&.downcase&.include?("to be determined") ||
        building.name&.downcase&.include?("tbd") ||
        building.abbreviation&.downcase == "tbd"
    end

    # Check if room is TBD/placeholder (room 0 or room name contains TBD)
    def tbd_room?(room)
      return false unless room

      # Room#number is a string column, so compare against the string "0".
      room.number.to_s == "0"
      # Note: Room model in production only has 'number', not 'name'
      # If room.name is added later, uncomment these lines:
      # room.name&.downcase&.include?("tbd") ||
      # room.name&.downcase&.include?("to be determined")
    end

    def final_exam_scope(time_scope)
      case time_scope
      when :future then FinalExam.where(exam_date: Time.zone.today..)
      when :past   then FinalExam.where(exam_date: ...Time.zone.today)
      else              FinalExam.all
      end
    end

    def university_event_scope(time_scope)
      case time_scope
      when :future then UniversityCalendarEvent.where("end_time IS NULL OR end_time >= ?", Time.current)
      when :past   then UniversityCalendarEvent.where("end_time < ?", Time.current)
      else              UniversityCalendarEvent.all
      end
    end

    private

    # If multiple meeting times exist for same day/time, prefer non-TBD over TBD
    def without_tbd_duplicates(meeting_times)
      meeting_times.group_by { |mt| [ mt.day_of_week, mt.begin_time, mt.end_time ] }
                   .map do |_key, group|
                     non_tbd = group.reject { |mt| (mt.building && tbd_building?(mt.building)) || (mt.room && tbd_room?(mt.room)) }
                     non_tbd.any? ? non_tbd.first : group.first
      end
    end
  end
end
