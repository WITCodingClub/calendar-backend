# frozen_string_literal: true

module CourseCalendars
  # The dates of one person's class meetings: the first meeting, the last day
  # of the weekly rule (before finals), and the days with no classes. The
  # calendar sync, the ICS feed, and the schedule API all read them here.
  #
  # The lookups of final exam dates, finals periods, and holidays are memoized
  # in this object, so they live as long as one sync.
  class RecurrenceBuilder
    attr_reader :user

    def initialize(user)
      @user = user
    end

    # A builder with the no-class events, the courses' final exam dates, and
    # the terms' finals dates loaded, for a response that lists a whole
    # schedule. Its lookups then send no query for each course or term.
    def self.preloaded(user, courses)
      new(user).tap { |builder| builder.preload_for!(courses) }
    end

    def preload_for!(courses)
      preload_holidays_for_user!
      preload_final_exam_dates!(courses.map(&:id))
      preload_term_finals_dates!(courses.map(&:term_id).uniq)
    end

    # One builder for each user, keyed by user id, for a response that lists
    # the schedules of many users. The final exam dates, the finals dates, and
    # the no-class events load once for all of the courses, so the number of
    # queries does not grow with the number of users. The courses must have
    # their meeting_times loaded: their date range picks the no-class events.
    def self.preloaded_for_users(users, courses)
      template = new(nil)
      template.preload_final_exam_dates!(courses.map(&:id).uniq)
      template.preload_term_finals_dates!(courses.map(&:term_id).uniq)
      template.preload_holidays_for_meeting_times!(courses.flat_map(&:meeting_times))

      users.to_h { |user| [ user.id, template.copy_for(user) ] }
    end

    # A new builder for the user that shares the loaded lookups of this one.
    # The lookups do not depend on the user.
    def copy_for(other_user)
      self.class.new(other_user).tap { |copy| copy.share_lookups_from(self) }
    end

    protected

    attr_reader :course_final_dates, :term_finals_start_dates, :term_finals_period_dates, :all_holidays_preloaded

    def share_lookups_from(other)
      @course_final_dates       = other.course_final_dates.dup
      @term_finals_start_dates  = other.term_finals_start_dates.dup
      @term_finals_period_dates = other.term_finals_period_dates.dup
      @all_holidays_preloaded   = other.all_holidays_preloaded
    end

    public

    def find_first_meeting_date(meeting_time)
      return nil if meeting_time.day_of_week.blank?

      # The enum stores the Date#wday number (Sunday is 0).
      target_wday = Course::MeetingTime.day_of_weeks[meeting_time.day_of_week]
      current_date = meeting_time.start_date.to_date

      7.times do
        return current_date if current_date.wday == target_wday

        current_date += 1.day
      end

      nil
    end

    # The local time on the date for an HHMM integer such as 1330.
    def time_on(date, time_int)
      return nil unless date && time_int

      SchoolTimeZone.zone.local(date.year, date.month, date.day, time_int / 100, time_int % 100)
    end

    # The weekly rule of the meeting time, until effective_end_date, without
    # the no-class days. start_time is the first meeting.
    def recurrence_for(meeting_time, start_time)
      return nil if meeting_time.day_of_week.blank?

      exdates = holiday_dates(meeting_time).map do |date|
        SchoolTimeZone.zone.local(date.year, date.month, date.day, start_time.hour, start_time.min, 0)
      end
      Recurrence.until_end_of(IceCube::Rule.weekly.day(meeting_time.day_of_week.to_sym),
                              effective_end_date(meeting_time), exdates: exdates)
    end

    # The last date the class can meet: meeting_time.end_date, cut back to
    # before finals week and Study Day. The stored end_date does not change.
    def effective_end_date(meeting_time)
      recurrence_end = meeting_time.end_date.to_date

      # The course's own final first; else the term's finals week, so that a
      # course with no linked exam still ends when finals start.
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

        # Study Day is a WIT no-class day before finals week, so classes also
        # end the day before the term's first finals-period event.
        study_day = earliest_finals_period_event_for_term(course.term_id)
        if study_day && (study_day - 1.day) < recurrence_end
          recurrence_end = study_day - 1.day
        end
      end

      recurrence_end
    end

    # The dates on the meeting day, from start_date to effective_end_date,
    # that a no-class event covers. These are the EXDATEs that calendar sync
    # adds, without the dates after the class stops.
    def excluded_dates(meeting_time)
      return [] if meeting_time.day_of_week.blank?

      range = meeting_time.start_date.to_date..effective_end_date(meeting_time)
      holiday_dates(meeting_time).select { |date| range.cover?(date) }.uniq.sort
    end

    # Loads the first final exam date of each course in one query, so that
    # effective_end_date sends no query for each course.
    def preload_final_exam_dates!(course_ids)
      @course_final_dates ||= {}
      dates = ::FinalExam.where(course_id: course_ids).where.not(exam_date: nil)
                         .group(:course_id).minimum(:exam_date)
      course_ids.each { |id| @course_final_dates[id] = dates[id] }
    end

    # Loads the start of finals week and the first finals-period event of
    # each term in two queries.
    def preload_term_finals_dates!(term_ids)
      @term_finals_start_dates ||= {}
      @term_finals_period_dates ||= {}
      starts  = ::FinalExam.finals_week_starts(term_ids)
      periods = ::UniversityCalendarEvent.finals_periods.where(term_id: term_ids).group(:term_id).minimum(:start_time)
      term_ids.each do |id|
        @term_finals_start_dates[id]  = starts[id]
        @term_finals_period_dates[id] = periods[id]&.to_date
      end
    end

    def final_exam_date_for_course(course_id)
      @course_final_dates ||= {}
      return @course_final_dates[course_id] if @course_final_dates.key?(course_id)

      @course_final_dates[course_id] = ::FinalExam.where(course_id: course_id)
                                                  .where.not(exam_date: nil)
                                                  .minimum(:exam_date)
    end

    def earliest_final_exam_date_for_term(term_id)
      @term_finals_start_dates ||= {}
      return @term_finals_start_dates[term_id] if @term_finals_start_dates.key?(term_id)

      @term_finals_start_dates[term_id] = ::FinalExam.finals_week_start(term_id)
    end

    def earliest_finals_period_event_for_term(term_id)
      @term_finals_period_dates ||= {}
      return @term_finals_period_dates[term_id] if @term_finals_period_dates.key?(term_id)

      @term_finals_period_dates[term_id] = ::UniversityCalendarEvent.finals_periods.where(term_id: term_id)
                                                                    .minimum(:start_time)&.to_date
    end

    # The dates on this meeting time's day that a no-class event in its date
    # range covers. A multi-day event gives each of its days on the meeting day.
    # @return [Array<Date>]
    def holiday_dates(meeting_time)
      target_wday = Course::MeetingTime.day_of_weeks[meeting_time.day_of_week]
      return [] if target_wday.nil?

      holidays_for_meeting_time(meeting_time).flat_map do |holiday|
        if holiday.end_time && holiday.start_time.to_date != holiday.end_time.to_date
          (holiday.start_time.to_date..holiday.end_time.to_date).select { |date| date.wday == target_wday }
        elsif holiday.start_time.wday == target_wday
          [ holiday.start_time.to_date ]
        else
          []
        end
      end
    end

    # The no-class spans in the meeting time's dates. After a preload it
    # filters the loaded spans and sends no query.
    # @return [Array<UniversityCalendarEvent::NoClassSpan>]
    def holidays_for_meeting_time(meeting_time)
      @holidays_cache ||= {}
      cache_key = [ meeting_time.start_date, meeting_time.end_date ]
      return @holidays_cache[cache_key] if @holidays_cache.key?(cache_key)

      if @all_holidays_preloaded
        # Compare dates: a Date against the local-midnight start_date becomes
        # midnight UTC and drops a holiday on the first day.
        mt_start = meeting_time.start_date.to_date
        mt_end   = meeting_time.end_date.to_date
        @holidays_cache[cache_key] = @all_holidays_preloaded.select do |h|
          h_start = h.start_time.to_date
          h_end   = (h.end_time || h.start_time).to_date
          h_end >= mt_start && h_start <= mt_end
        end
      else
        @holidays_cache[cache_key] = UniversityCalendarEvent.no_class_spans_between(
          meeting_time.start_date,
          meeting_time.end_date
        )
      end
    end

    # Loads the no-class spans over the dates of all the user's meeting times.
    def preload_holidays_for_user!
      dates = user.enrollments.joins(course: :meeting_times)
                  .pluck("course_meeting_times.start_date", "course_meeting_times.end_date")
      preload_holidays_between!(dates.map(&:first).compact.min, dates.map(&:last).compact.max)
    end

    # The same as preload_holidays_for_user!, for meeting times that are
    # already loaded. It sends no query for the dates.
    def preload_holidays_for_meeting_times!(meeting_times)
      preload_holidays_between!(meeting_times.filter_map(&:start_date).min,
                                meeting_times.filter_map(&:end_date).max)
    end

    def preload_holidays_between!(min_start, max_end)
      @all_holidays_preloaded = if min_start && max_end
                                  UniversityCalendarEvent.no_class_spans_between(min_start, max_end)
      else
                                  []
      end
    end
  end
end
