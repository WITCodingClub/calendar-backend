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
# Times are wall-clock times in the app time zone (Time.zone).
#
# Each kind of busy time comes from a source. A source is a class with
# `.call(user, from, to)` that returns `BusyBlocks::Interval` values. The list
# is in `BusyBlocks.sources`. To add a new kind of busy time (for example
# meetings), write a source and add it to that list. The merge step, the
# serializer, and both API routes then include it with no other change.
#
# - MeetingSource: class meetings, minus the days with no classes (holidays,
#   study days, and the finals period).
# - FinalExamSource: the final exams of the user.
#
#   BusyBlocks.new(user, from: Date.new(2026, 10, 5), to: Date.new(2026, 10, 9)).call
#   # => [#<data BusyBlocks::Block date=2026-10-05, start="09:00", end="10:15">, ...]
class BusyBlocks
  MAX_DAYS = 120

  # One busy time from one source. +begin_time+ and +end_time+ are HHMM integers.
  Interval = Data.define(:date, :begin_time, :end_time)

  # The sources that make up the busy time of a user.
  def self.sources = [ MeetingSource, FinalExamSource ]

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
    by_date = self.class.sources.flat_map { |source| source.call(@user, @from, @to) }.group_by(&:date)

    (@from..@to).flat_map do |date|
      ranges = by_date.fetch(date, []).map { |interval| [ interval.begin_time, interval.end_time ] }
      merge(ranges).map do |begin_time, end_time|
        Block.new(date: date, start: hhmm(begin_time), end: hhmm(end_time))
      end
    end
  end

  private

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
