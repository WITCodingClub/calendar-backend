# frozen_string_literal: true

class BusyBlocks
  # The saved friend meetings of a user: the meetings the user owns, and the
  # meetings that invited the user. It is the same set that the user can read
  # at GET /api/friends/meetings. A cancelled meeting is not busy time.
  #
  # A meeting is busy time on a day with no classes too, because it is not a
  # class. Only the times leave this source, so a friend who shares only
  # availability learns nothing about the meeting.
  class FriendMeetingSource
    # The end time of an occurrence that goes on past midnight.
    END_OF_DAY = 2400

    def self.call(user, from, to) = new(user, from, to).call

    def initialize(user, from, to)
      @user        = user
      @range_start = from.in_time_zone.beginning_of_day
      @range_end   = (to + 1).in_time_zone.beginning_of_day
    end

    def call
      meetings.flat_map do |meeting|
        meeting.occurrences_between(@range_start, @range_end).flat_map do |starts_at, ends_at|
          intervals(starts_at.in_time_zone, ends_at.in_time_zone)
        end
      end
    end

    private

    def meetings
      FriendMeeting.live.where(user_id: @user.id).or(FriendMeeting.live.inviting(@user))
                   .overlapping(@range_start, @range_end).to_a
    end

    # One interval for each date that the occurrence covers, inside the range.
    def intervals(starts_at, ends_at)
      (starts_at.to_date..ends_at.to_date).filter_map do |date|
        next unless date.between?(@range_start.to_date, (@range_end - 1).to_date)

        begin_time = date == starts_at.to_date ? hhmm(starts_at) : 0
        end_time   = date == ends_at.to_date ? hhmm(ends_at) : END_OF_DAY
        Interval.new(date: date, begin_time: begin_time, end_time: end_time) if end_time > begin_time
      end
    end

    def hhmm(time) = (time.hour * 100) + time.min
  end
end
