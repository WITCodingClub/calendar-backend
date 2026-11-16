# frozen_string_literal: true

module CourseCalendars
  # Builds the events that one person's calendar must hold: class meetings,
  # final exams, and university events, as CourseCalendars::Event values with
  # the person's preferences applied. The Google and Outlook sync sends them
  # (see CourseCalendars::Providers), and the ICS feed renders them.
  class EventBuilder
    COURSE_INCLUDES = [ :term, :faculties, { meeting_times: [ :meeting_time_rooms, { rooms: :building }, { course: [ :faculties, :term ] } ] } ].freeze

    attr_reader :user, :recurrence

    def initialize(user, recurrence: RecurrenceBuilder.new(user), preferences: Preferences::Applier.new(user))
      @user        = user
      @recurrence  = recurrence
      @preferences = preferences
    end

    # The person's courses, with what their class events read.
    def self.courses_of(user)
      user.courses.includes(COURSE_INCLUDES).to_a
    end

    # The class events of courses loaded with COURSE_INCLUDES. Of meeting
    # times with the same day and hours, one is kept
    # (Course#filtered_meeting_times).
    def class_events(courses = self.class.courses_of(user))
      recurrence.preload_for!(courses)
      courses.flat_map do |course|
        course.filtered_meeting_times.filter_map { |meeting_time| meeting_time_event(meeting_time) }
      end
    end

    # time_scope: :future (exams today or later) or :past (for the historical
    # backfill).
    def final_exam_events(time_scope: :future)
      course_ids = user.enrollments.pluck(:course_id)
      return [] if course_ids.empty?

      exams = FinalExam.where(course_id: course_ids)
      exams = time_scope == :past ? exams.where(exam_date: ...Time.zone.today) : exams.where(exam_date: Time.zone.today..)
      exams.includes(:term, course: [ :faculties, :term ]).find_each.filter_map { |final_exam| final_exam_event(final_exam) }
    end

    # The holidays, then the other categories the person syncs
    # (UniversityCalendarEvent.categories_wanted_by). time_scope: :future (not
    # ended yet), :past (for the historical backfill), or a Range of dates
    # that the events overlap.
    def university_events(time_scope: :future)
      scope  = university_event_scope(time_scope).includes(:term)
      others = UniversityCalendarEvent.categories_wanted_by(user) - [ UniversityCalendarEvent::HOLIDAY ]

      events = UniversityCalendarEvent.holidays.merge(scope).find_each.map do |event|
        university_event(event, summary: event.formatted_holiday_summary, all_day: true)
      end
      return events if others.empty?

      events + UniversityCalendarEvent.by_categories(others).merge(scope).find_each.map do |event|
        university_event(event, summary: event.summary, all_day: event.all_day || false)
      end
    end

    private

    attr_reader :preferences

    def university_event_scope(time_scope)
      case time_scope
      when :future then UniversityCalendarEvent.where("end_time IS NULL OR end_time >= ?", Time.current)
      when :past   then UniversityCalendarEvent.where(end_time: ...Time.current)
      when Range   then UniversityCalendarEvent.in_date_range(time_scope.begin, time_scope.end)
      end
    end

    def meeting_time_event(meeting_time)
      first_meeting_date = recurrence.find_first_meeting_date(meeting_time)
      return nil unless first_meeting_date

      start_time = recurrence.time_on(first_meeting_date, meeting_time.begin_time)
      end_time   = recurrence.time_on(first_meeting_date, meeting_time.end_time)
      return nil unless start_time && end_time

      course = meeting_time.course
      build(meeting_time,
            summary: course.title,
            description: [ course.subject, course.course_number, course.section_number ].compact.join("-"),
            location: meeting_time.location_text,
            start_time: start_time,
            end_time: end_time,
            recurrence: recurrence.recurrence_for(meeting_time, start_time),
            all_day: meeting_time.all_day?,
            changed_at: [
              course.updated_at,
              meeting_time.updated_at,
              *course.faculties.map(&:updated_at),
              *meeting_time.meeting_time_rooms.map(&:updated_at),
              *meeting_time.rooms.map(&:updated_at),
              *meeting_time.rooms.filter_map { |room| room.building&.updated_at },
              *recurrence.holidays_for_meeting_time(meeting_time).map(&:updated_at)
            ])
    end

    def final_exam_event(final_exam)
      return nil unless final_exam.start_datetime && final_exam.end_datetime

      course = final_exam.course
      build(final_exam,
            summary: "Final Exam: #{final_exam.course_title}",
            description: final_exam.course_code,
            location: final_exam.location_with_names,
            start_time: final_exam.start_datetime,
            end_time: final_exam.end_datetime,
            changed_at: [ final_exam.updated_at, final_exam.term&.updated_at, course&.updated_at,
                          *course&.faculties&.map(&:updated_at) ])
    end

    def university_event(event, summary:, all_day:)
      build(event,
            summary: summary,
            description: event.description,
            location: event.location,
            start_time: event.start_time,
            end_time: event.end_time,
            all_day: all_day,
            changed_at: [ event.updated_at, event.term&.updated_at ])
    end

    # changed_at also counts the person's preference rows and the code that
    # shapes events (Event::LOGIC_CHANGED_AT).
    def build(source, changed_at:, **fields)
      changed_at = [ *changed_at, preferences.changed_at_for(source), Event::LOGIC_CHANGED_AT ].compact.max
      preferences.apply(Event.new(source: source, changed_at: changed_at, **fields))
    end
  end
end
