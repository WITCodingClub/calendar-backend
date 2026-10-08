# frozen_string_literal: true

class BusyBlocks
  # Class meetings of a user. A meeting does not happen on a day with no classes
  # (a holiday, a study day, or the finals period). The same rule removes
  # those days from the calendar events of the user.
  class MeetingSource
    Row = Data.define(:day_of_week, :begin_time, :end_time, :start_date, :end_date) do
      def covers?(date) = date.between?(start_date, end_date)
    end

    def self.call(user, from, to) = new(user, from, to).call

    def initialize(user, from, to)
      @user = user
      @from = from
      @to   = to
    end

    def call
      by_weekday  = rows.group_by(&:day_of_week)
      no_class    = no_class_dates

      (@from..@to).flat_map do |date|
        next [] if no_class.include?(date)

        by_weekday.fetch(date.wday, []).select { |row| row.covers?(date) }.map do |row|
          Interval.new(date: date, begin_time: row.begin_time, end_time: row.end_time)
        end
      end
    end

    private

    # One query, whatever the number of classes. It reads only the columns that a
    # block needs, so no course record is loaded at all.
    def rows
      Course::MeetingTime
        .joins(course: :enrollments)
        .where(enrollments: { user_id: @user.id })
        .where(start_date: ..@to.in_time_zone.end_of_day)
        .where(end_date: @from.in_time_zone.beginning_of_day..)
        .distinct
        .pluck(Arel.sql("course_meeting_times.day_of_week"), :begin_time, :end_time,
               Arel.sql("course_meeting_times.start_date"), Arel.sql("course_meeting_times.end_date"))
        .map do |day_of_week, begin_time, end_time, start_date, end_date|
          # Rails casts the enum column to its name ("monday"). Date#wday uses
          # the same numbers as the enum (Sunday is 0).
          Row.new(day_of_week: Course::MeetingTime.day_of_weeks.fetch(day_of_week), begin_time:, end_time:,
                  start_date: start_date.in_time_zone.to_date, end_date: end_date.in_time_zone.to_date)
        end
    end

    # Every date in the range that a university calendar event marks as a day
    # with no classes. A multi-day event covers each date from its start to its
    # end, as for the holiday exclusions of the calendar events.
    def no_class_dates
      UniversityCalendarEvent.no_class_days_between(@from, @to).pluck(:start_time, :end_time).flat_map do |start_time, end_time|
        first = start_time.in_time_zone.to_date
        last  = [ end_time.in_time_zone.to_date, first ].max
        (first..last).to_a
      end.to_set
    end
  end
end
