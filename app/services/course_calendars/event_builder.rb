# frozen_string_literal: true

module CourseCalendars
  # Builds the events that one person's calendar must hold: class meetings,
  # final exams, and university events, as provider-neutral hashes. The
  # Google and Outlook sync sends them (see CourseCalendars::Providers), and
  # the ICS feed renders them as iCalendar.
  #
  # With preferences (a Preferences::Applier), each event has the person's
  # templates and color applied. The providers apply them on their own.
  #
  # This class only reads the database. It does not call a provider.
  class EventBuilder
    # One event and the record it came from.
    Entry = Data.define(:source, :event)

    attr_reader :user, :recurrence

    def initialize(user, recurrence: RecurrenceBuilder.new(user), preferences: nil)
      @user        = user
      @recurrence  = recurrence
      @preferences = preferences
    end

    # Loads the holidays of all the person's meeting times in one query, so the
    # EXDATE lines of each meeting time do not send a query each.
    def preload_holidays!
      recurrence.preload_holidays_for_user!
    end

    # The events of every meeting time of the given enrollments.
    # @param prefer_valid_locations [Boolean] keep one meeting time for each
    #   day and hours (Course#filtered_meeting_times)
    def course_events(enrollment_scope, prefer_valid_locations:)
      courses = enrollment_scope.includes(course: [ meeting_times: [ rooms: :building ] ]).find_each.map(&:course)
      class_entries(courses, prefer_valid_locations: prefer_valid_locations).map(&:event)
    end

    # The class events of courses whose meeting times are loaded.
    def class_entries(courses, prefer_valid_locations: true)
      courses.flat_map do |course|
        meeting_times = prefer_valid_locations ? course.filtered_meeting_times : course.meeting_times
        meeting_times.filter_map do |meeting_time|
          event = base_meeting_time_event(meeting_time, course)
          entry(meeting_time, event) if event
        end
      end
    end

    # The event of one meeting time, or nil when it has no first meeting date.
    def meeting_time_event(meeting_time, course = meeting_time.course)
      event = base_meeting_time_event(meeting_time, course)
      event && with_preferences(meeting_time, event)
    end

    # The event of one final exam, or nil when the exam has no start or end.
    def final_exam_event(final_exam)
      event = base_final_exam_event(final_exam)
      event && with_preferences(final_exam, event)
    end

    # time_scope: :future (exams today or later), :past (for the historical
    # backfill), or :all.
    def finals_events(time_scope: :future)
      final_exam_entries(time_scope: time_scope).map(&:event)
    end

    def final_exam_entries(time_scope: :future)
      course_ids = user.enrollments.pluck(:course_id)
      return [] if course_ids.empty?

      ::FinalExam.where(course_id: course_ids)
                 .merge(final_exam_scope(time_scope))
                 .includes(:term, course: [ :faculties, :term ])
                 .find_each
                 .filter_map do |final_exam|
                   event = base_final_exam_event(final_exam)
                   entry(final_exam, event) if event
                 end
    end

    # Every holiday, and the categories the person chose to sync.
    # time_scope: :future (not ended yet), :past (for the historical
    # backfill), :all, or a Range of dates that the events overlap.
    def university_events(time_scope: :future)
      university_event_entries(time_scope: time_scope).map(&:event)
    end

    def university_event_entries(time_scope: :future)
      scope = university_event_scope(time_scope).includes(:term)

      entries = UniversityCalendarEvent.holidays.merge(scope).find_each.map do |event|
        entry(event, university_event(event, summary: event.formatted_holiday_summary, all_day: true))
      end

      categories = synced_categories
      return entries if categories.empty?

      entries + UniversityCalendarEvent.by_categories(categories).merge(scope).find_each.map do |event|
        entry(event, university_event(event, summary: event.summary, all_day: event.all_day || false))
      end
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
      when Range   then UniversityCalendarEvent.in_date_range(time_scope.begin, time_scope.end)
      else              UniversityCalendarEvent.all
      end
    end

    private

    def entry(source, event) = Entry.new(source: source, event: with_preferences(source, event))

    def with_preferences(source, event)
      @preferences ? @preferences.apply(source, event) : event
    end

    def base_meeting_time_event(meeting_time, course)
      return nil if meeting_time.day_of_week.blank?

      first_meeting_date = recurrence.find_first_meeting_date(meeting_time)
      return nil unless first_meeting_date

      start_time = recurrence.parse_time(first_meeting_date, meeting_time.begin_time)
      end_time   = recurrence.parse_time(first_meeting_date, meeting_time.end_time)
      return nil unless start_time && end_time

      course_code     = [ course.subject, course.course_number, course.section_number ].compact.join("-")
      recurrence_rule = recurrence.build_recurrence_rule(meeting_time)

      {
        summary: course.title,
        description: course_code,
        location: meeting_time.location_text,
        start_time: start_time,
        end_time: end_time,
        course_code: course_code,
        meeting_time_id: meeting_time.id,
        recurrence: recurrence.build_recurrence_with_exclusions(meeting_time, recurrence_rule, start_time),
        all_day: meeting_time.all_day?
      }
    end

    def base_final_exam_event(final_exam)
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

    def university_event(event, summary:, all_day:)
      {
        summary: summary,
        description: event.description,
        location: event.location,
        start_time: event.start_time,
        end_time: event.end_time,
        university_calendar_event_id: event.id,
        all_day: all_day,
        recurrence: nil
      }
    end

    def synced_categories
      config = user.user_extension_config
      config&.sync_university_events ? config.synced_university_event_categories : []
    end
  end
end
