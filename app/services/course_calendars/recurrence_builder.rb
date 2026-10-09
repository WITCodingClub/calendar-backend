# frozen_string_literal: true

module CourseCalendars
  # Builds the dates, times, and recurrence lines of one person's course events.
  #
  # The lookups of final exam dates, finals periods, and holidays are memoized
  # in this object. CourseScheduleSyncable keeps one instance for each user
  # object, so the caches live as long as the user object, as they did when
  # they were instance variables of the user.
  class RecurrenceBuilder
    attr_reader :user

    def initialize(user)
      @user = user
    end

    def find_first_meeting_date(meeting_time)
      return nil if meeting_time.day_of_week.blank?

      # Get the numeric day of week (0=Sunday, 1=Monday, etc.)
      # The enum value is already stored as the integer wday value
      target_wday = Course::MeetingTime.day_of_weeks[meeting_time.day_of_week]

      # Start from the meeting start_date
      current_date = meeting_time.start_date.to_date

      # Find the first day that matches the meeting day (max 7 days search)
      7.times do
        return current_date if current_date.wday == target_wday

        current_date += 1.day
      end

      nil
    end

    def parse_time(date, time_int)
      return nil unless date && time_int

      # Convert integer time (e.g., 900 = 9:00 AM, 1330 = 1:30 PM)
      hours = time_int / 100
      minutes = time_int % 100

      # Create time in configured timezone (Eastern Time)
      Time.zone.local(date.year, date.month, date.day, hours, minutes)
    end

    def build_recurrence_rule(meeting_time)
      return nil if meeting_time.day_of_week.blank?

      # Determine the end date for recurrence
      # Use meeting_time.end_date, but stop before finals week if THIS COURSE has a final
      recurrence_end = meeting_time.end_date.to_date

      # Stop recurrence before finals week.
      # Try course-specific final first; fall back to the term's earliest final so
      # that courses with no linked exam still end at the start of finals week.
      course = meeting_time.course
      if course
        course_final = final_exam_date_for_course(course.id)
        if course_final && course_final < recurrence_end
          recurrence_end = course_final - 1.day
        else
          term_finals_start = earliest_final_exam_date_for_term(course.term_id)
          if term_finals_start && term_finals_start < recurrence_end
            recurrence_end = term_finals_start - 1.day
          end
        end

        # Also stop the day before Study Day (earliest finals-period UCE for the term).
        # Study Day is a university-designated no-class day preceding finals week,
        # so regular class recurrences should end the day before it begins.
        study_day = earliest_finals_period_event_for_term(course.term_id)
        if study_day && (study_day - 1.day) < recurrence_end
          recurrence_end = study_day - 1.day
        end
      end

      # Build weekly recurrence rule using ice_cube and export to iCalendar format.
      # UNTIL must be end-of-day in the *local* zone expressed as UTC. Using bare
      # Time.utc(...,23,59,59) drops the final occurrence of evening (Eastern)
      # classes, whose start instant falls after midnight UTC.
      until_time = Time.zone.local(recurrence_end.year, recurrence_end.month, recurrence_end.day, 23, 59, 59).utc
      rule = IceCube::Rule.weekly.day(meeting_time.day_of_week.to_sym).until(until_time)
      "RRULE:#{rule.to_ical}"
    end

    # Memoized lookup of final exam date for a specific course
    # Avoids N+1 queries when building recurrence rules for multiple meeting times
    # Returns nil if the course doesn't have a final exam
    def final_exam_date_for_course(course_id)
      @course_final_dates ||= {}
      return @course_final_dates[course_id] if @course_final_dates.key?(course_id)

      @course_final_dates[course_id] = ::FinalExam.where(course_id: course_id)
                                                  .where.not(exam_date: nil)
                                                  .minimum(:exam_date)
    end

    # Memoized lookup of the earliest final exam date across an entire term.
    # Used as a fallback so courses without a linked final still stop recurring
    # at the start of finals week rather than running through to term end_date.
    def earliest_final_exam_date_for_term(term_id)
      @term_finals_start_dates ||= {}
      return @term_finals_start_dates[term_id] if @term_finals_start_dates.key?(term_id)

      @term_finals_start_dates[term_id] = ::FinalExam.where(term_id: term_id)
                                                     .where.not(exam_date: nil)
                                                     .minimum(:exam_date)
    end

    # Memoized lookup of the earliest finals-period university calendar event for a term.
    # Matches UCEs with category "finals" and a summary containing "Final Exam Period" or
    # "Study Day" — deliberately excludes announcement events like "Final Exam Schedule Online"
    # which share the same category but are not actual no-class days.
    def earliest_finals_period_event_for_term(term_id)
      @term_finals_period_dates ||= {}
      return @term_finals_period_dates[term_id] if @term_finals_period_dates.key?(term_id)

      @term_finals_period_dates[term_id] = ::UniversityCalendarEvent
                                           .where(term_id: term_id, category: "finals")
                                           .where("summary ILIKE ? OR summary ILIKE ?", "%Final Exam Period%", "%Study Day%")
                                           .minimum(:start_time)
                                           &.to_date
    end

    # Build recurrence array with RRULE and EXDATE entries for holidays
    # @param meeting_time [MeetingTime] The meeting time object
    # @param recurrence_rule [String, nil] The RRULE string
    # @param start_time [Time] The start time of the first meeting
    # @return [Array<String>, nil] Array of recurrence rules including EXDATEs, or nil
    def build_recurrence_with_exclusions(meeting_time, recurrence_rule, start_time)
      return nil unless recurrence_rule

      recurrence = [ recurrence_rule ]

      # Get holiday dates that should be excluded from this meeting time
      exdates = build_holiday_exdates(meeting_time, start_time)
      recurrence.concat(exdates) if exdates.any?

      recurrence
    end

    # Build EXDATE strings for holidays that fall on this meeting time's day
    # @param meeting_time [MeetingTime] The meeting time object
    # @param start_time [Time] The start time of meetings (for time component)
    # @return [Array<String>] Array of EXDATE strings
    def build_holiday_exdates(meeting_time, start_time)
      return [] unless defined?(UniversityCalendarEvent)

      # Get the numeric day of week (0=Sunday, 1=Monday, etc.)
      target_wday = Course::MeetingTime.day_of_weeks[meeting_time.day_of_week]
      return [] if target_wday.nil?

      # Get all holidays during the course date range
      holidays = holidays_for_meeting_time(meeting_time)
      return [] if holidays.empty?

      # Filter to holidays that have any day falling on this meeting day
      matching_holidays = holidays.select do |holiday|
        if holiday.end_time && holiday.start_time.to_date != holiday.end_time.to_date
          # Multi-day event: check if any day in the range matches target weekday
          (holiday.start_time.to_date..holiday.end_time.to_date).any? { |date| date.wday == target_wday }
        else
          # Single-day event: check if the day matches
          holiday.start_time.wday == target_wday
        end
      end

      # Build EXDATE strings for all matching dates
      exdates = []
      matching_holidays.each do |holiday|
        if holiday.end_time && holiday.start_time.to_date != holiday.end_time.to_date
          # Multi-day: add EXDATE for each matching weekday in the range
          (holiday.start_time.to_date..holiday.end_time.to_date).each do |date|
            exdates << format_exdate(date, start_time) if date.wday == target_wday
          end
        else
          # Single-day: add one EXDATE
          exdates << format_exdate(holiday.start_time.to_date, start_time)
        end
      end

      exdates
    end

    # Get holidays that apply to a meeting time's date range.
    # Filters from the preloaded set (populated by preload_holidays_for_user!) to avoid
    # per-meeting-time DB queries when multiple meeting times have different date ranges.
    # @param meeting_time [MeetingTime] The meeting time to get holidays for
    # @return [Array<UniversityCalendarEvent>] Holiday events in the date range
    def holidays_for_meeting_time(meeting_time)
      @holidays_cache ||= {}
      cache_key = [ meeting_time.start_date, meeting_time.end_date ]
      return @holidays_cache[cache_key] if @holidays_cache.key?(cache_key)

      if @all_holidays_preloaded
        # Filter from the preloaded set in memory — no additional DB query
        mt_start = meeting_time.start_date
        mt_end   = meeting_time.end_date
        @holidays_cache[cache_key] = @all_holidays_preloaded.select do |h|
          h_start = h.start_time.to_date
          h_end   = (h.end_time || h.start_time).to_date
          h_end >= mt_start && h_start <= mt_end
        end
      else
        @holidays_cache[cache_key] = UniversityCalendarEvent.no_class_days_between(
          meeting_time.start_date,
          meeting_time.end_date
        ).to_a
      end
    end

    # Preload all holidays for the full date range of this user's enrolled meeting times.
    # Stores in @all_holidays_preloaded so holidays_for_meeting_time can filter in memory.
    def preload_holidays_for_user!
      return unless defined?(UniversityCalendarEvent)

      # Collect start/end dates from all enrolled meeting times without re-querying later
      dates = user.enrollments.joins(course: :meeting_times)
                  .pluck("course_meeting_times.start_date", "course_meeting_times.end_date")
      min_start = dates.map(&:first).compact.min
      max_end   = dates.map(&:last).compact.max

      @all_holidays_preloaded = if min_start && max_end
                                  UniversityCalendarEvent.no_class_days_between(min_start, max_end).to_a
      else
                                  []
      end
    end

    # Format an EXDATE string for Google Calendar
    # Uses date-time format matching the event's start time
    # @param date [Date] The date to exclude
    # @param start_time [Time] The event start time (for hour/minute)
    # @return [String] Formatted EXDATE string
    def format_exdate(date, start_time)
      # Build the exclusion datetime using the date and the meeting's time
      exclusion_time = Time.zone.local(
        date.year, date.month, date.day,
        start_time.hour, start_time.min, 0
      )

      # Format as EXDATE with timezone
      # Google Calendar expects: EXDATE;TZID=America/New_York:20241128T090000
      timezone = Time.zone.tzinfo.name
      formatted_time = exclusion_time.strftime("%Y%m%dT%H%M%S")
      "EXDATE;TZID=#{timezone}:#{formatted_time}"
    end
  end
end
