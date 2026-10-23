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

    def self.call(user, from, to) = call_many([ user ], from, to).fetch(user.id, [])

    # { user id => [Interval] }, in two queries for any number of users.
    def self.call_many(users, from, to) = new(users, from, to).call

    def initialize(users, from, to)
      @user_ids    = users.map(&:id)
      @range_start = from.in_time_zone.beginning_of_day
      @range_end   = (to + 1).in_time_zone.beginning_of_day
    end

    def call
      found   = meetings
      invited = invited_user_ids(found)

      found.each_with_object({}) do |meeting, by_user|
        times = meeting.occurrences_between(@range_start, @range_end).flat_map do |starts_at, ends_at|
          intervals(starts_at.in_time_zone, ends_at.in_time_zone)
        end
        next if times.empty?

        people = (@user_ids & [ meeting.user_id ]) | (meeting.invite_friends? ? invited.fetch(meeting.id, []) : [])
        people.each { |user_id| (by_user[user_id] ||= []).concat(times) }
      end
    end

    private

    # FriendMeeting.inviting, for many users at once.
    def meetings
      inviting = FriendMeeting.live.where(invite_friends: true)
                              .where(id: FriendMeetingAttendee.where(user_id: @user_ids).select(:friend_meeting_id))
      FriendMeeting.live.where(user_id: @user_ids).or(inviting)
                   .overlapping(@range_start, @range_end).to_a
    end

    # { meeting id => [user id] } for the users that each meeting invited.
    def invited_user_ids(meetings)
      FriendMeetingAttendee.where(friend_meeting_id: meetings.map(&:id), user_id: @user_ids)
                           .pluck(:friend_meeting_id, :user_id)
                           .group_by(&:first).transform_values { |rows| rows.map(&:last) }
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
