# frozen_string_literal: true

# Lists the times that a user is in class, between two dates, with no course
# data: only the date and the start and end time of each block.
#
# A friend who shares only availability (Friendship "availability_only") gets
# this list in place of the course list. The free-time search on the client
# needs nothing more.
#
# Blocks on one date that overlap or touch are merged into one block, so the
# list does not show how many classes fill a block either.
#
# Times are wall-clock times in the app time zone (Time.zone). The service does
# not remove holidays or other days with no classes: a block on such a day only
# says "busy" when the user is free, which is the safe side.
#
#   BusyBlocks.new(user, from: Date.new(2026, 10, 5), to: Date.new(2026, 10, 9)).call
#   # => [#<data BusyBlocks::Block date=2026-10-05, start="09:00", end="10:15">, ...]
class BusyBlocks
  MAX_DAYS = 120

  Block = Data.define(:date, :start, :end) do
    def weekday = date.strftime("%A").downcase
  end

  def initialize(user, from:, to:)
    raise ArgumentError, "to must not be before from" if to < from
    raise ArgumentError, "the range must be #{MAX_DAYS} days or fewer" if (to - from).to_i + 1 > MAX_DAYS

    @user = user
    @from = from
    @to   = to
  end

  # Returns the blocks sorted by date, then start time.
  def call
    by_weekday = meeting_rows.group_by(&:day_of_week)

    (@from..@to).flat_map do |date|
      rows = by_weekday.fetch(date.wday, []).select { |row| row.covers?(date) }
      merge(rows.map { |row| [ row.begin_time, row.end_time ] }).map do |begin_time, end_time|
        Block.new(date: date, start: hhmm(begin_time), end: hhmm(end_time))
      end
    end
  end

  private

  Row = Data.define(:day_of_week, :begin_time, :end_time, :start_date, :end_date) do
    def covers?(date) = date.between?(start_date, end_date)
  end

  # One query, whatever the number of classes. It reads only the columns that a
  # block needs, so no course record is loaded at all.
  def meeting_rows
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

  # Merges [begin, end] pairs (HHMM integers) that overlap or touch.
  def merge(ranges)
    ranges.sort.each_with_object([]) do |(begin_time, end_time), merged|
      if merged.any? && begin_time <= merged.last[1]
        merged.last[1] = [ merged.last[1], end_time ].max
      else
        merged << [ begin_time, end_time ]
      end
    end
  end

  def hhmm(time) = format("%02d:%02d", time / 100, time % 100)
end
