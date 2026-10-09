# frozen_string_literal: true

module CourseCalendars
  class IcsFeed
    # The days with no classes (holidays, study days, finals) that fall in the
    # dates of each meeting time. One query loads them for all the courses.
    class Holidays
      def initialize(courses)
        @cache = preload(courses)
      end

      # The no-class days in the dates of the meeting time.
      def for(meeting_time)
        cache_key = [ meeting_time.start_date, meeting_time.end_date ]
        @cache[cache_key] ||= UniversityCalendarEvent.no_class_days_between(
          meeting_time.start_date,
          meeting_time.end_date
        ).to_a
      end

      # The class starts that a no-class day cancels, at the hour and minute of
      # start_time. A holiday of more than one day cancels each matching weekday.
      def exdates_for(meeting_time, start_time)
        target_wday = Course::MeetingTime.day_of_weeks[meeting_time.day_of_week]
        return [] if target_wday.nil?

        exdates = []

        self.for(meeting_time).each do |holiday|
          is_multi_day = holiday.end_time && holiday.start_time.to_date != holiday.end_time.to_date

          if is_multi_day
            (holiday.start_time.to_date..holiday.end_time.to_date).each do |date|
              next unless date.wday == target_wday

              exdates << Time.zone.local(date.year, date.month, date.day, start_time.hour, start_time.min, 0)
            end
          elsif holiday.start_time.wday == target_wday
            exdates << Time.zone.local(
              holiday.start_time.year, holiday.start_time.month, holiday.start_time.day,
              start_time.hour, start_time.min, 0
            )
          end
        end

        exdates
      end

      private

      def preload(courses)
        meeting_times = courses.flat_map { |c| c.meeting_times.to_a }
        return {} if meeting_times.empty?

        min_date = meeting_times.filter_map(&:start_date).min
        max_date = meeting_times.filter_map(&:end_date).max
        return {} unless min_date && max_date

        all_no_class_days = UniversityCalendarEvent.no_class_days_between(min_date, max_date).to_a

        meeting_times.map { |mt| [ mt.start_date, mt.end_date ] }.uniq.each_with_object({}) do |(start_date, end_date), cache|
          cache[[ start_date, end_date ]] = all_no_class_days.select do |h|
            h.start_time.to_date <= end_date && h.end_time.to_date >= start_date
          end
        end
      end
    end
  end
end
