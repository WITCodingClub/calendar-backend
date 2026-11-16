# frozen_string_literal: true

module MeetingLinks
  # Lists the times that a meeting link offers: each start time, on a weekday in
  # the link's date range, when the owner is free for the whole meeting length.
  # With a signed-in guest, the guest must be free too.
  #
  # Busy time comes from BusyBlocks: classes, final exams, and friend
  # meetings, with no course data. The answer holds only start and end times,
  # so the public page can show nothing else.
  #
  #   MeetingLinks::Slots.new(link).call
  #   # => [#<data MeetingLinks::Slots::Slot start_time=..., end_time=...>, ...]
  class Slots
    DAY_START   = 8 * 60  # 08:00, in minutes after midnight
    DAY_END     = 21 * 60 # 21:00
    STEP        = 30.minutes
    MIN_NOTICE  = 1.hour

    Slot = Data.define(:start_time, :end_time) do
      def date = start_time.to_date
    end

    def initialize(link, guest: nil, now: Time.current)
      @link  = link
      @guest = guest
      @now   = now
    end

    def call
      busy = busy_times(@link.user)
      busy += busy_times(@guest) if @guest && @guest != @link.user

      days.flat_map do |date|
        day_slots(date).reject { |slot| busy.any? { |from, to| from < slot.end_time && to > slot.start_time } }
      end
    end

    # The slot that starts at the given time, or nil when it is not free.
    def find(start_time)
      call.find { |slot| slot.start_time == start_time }
    end

    private

    def days
      @days ||= begin
        first = [ @link.starts_on, @now.in_time_zone.to_date ].max
        (first..@link.ends_on).select(&:on_weekday?)
      end
    end

    def day_slots(date)
      midnight = date.in_time_zone.beginning_of_day
      earliest = @now + MIN_NOTICE
      starts   = (DAY_START..(DAY_END - @link.duration_minutes)).step(STEP.in_minutes.to_i)

      starts.filter_map do |minutes|
        start_time = midnight + minutes.minutes
        Slot.new(start_time: start_time, end_time: start_time + @link.duration) if start_time >= earliest
      end
    end

    # [from, to] pairs of Time for the whole range.
    def busy_times(user)
      return [] if days.empty?

      BusyBlocks.new(user, from: days.first, to: days.last).call.map do |block|
        [ at(block.date, block.start), at(block.date, block.end) ]
      end
    end

    # "24:00" is the midnight after the date (a friend meeting that goes on
    # past midnight).
    def at(date, hhmm)
      hours, minutes = hhmm.split(":").map(&:to_i)
      return (date + 1).in_time_zone.beginning_of_day if hours == 24

      date.in_time_zone.change(hour: hours, min: minutes)
    end
  end
end
