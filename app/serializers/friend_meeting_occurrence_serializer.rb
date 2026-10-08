# frozen_string_literal: true

# One occurrence of a FriendMeeting in GET /api/friends/meetings. The id is
# the meeting id and the occurrence start in UTC, so it stays the same until
# the owner moves the meeting.
class FriendMeetingOccurrenceSerializer
  def initialize(meeting, starts_at, ends_at)
    @meeting   = meeting
    @starts_at = starts_at
    @ends_at   = ends_at
  end

  def self.occurrence_id(meeting, starts_at)
    "#{meeting.public_id}:#{starts_at.utc.iso8601}"
  end

  def as_json(*)
    {
      id:         self.class.occurrence_id(@meeting, @starts_at),
      meeting_id: @meeting.public_id,
      start_time: @starts_at.in_time_zone(FriendMeeting::LOCAL_TIME_ZONE).iso8601,
      end_time:   @ends_at.in_time_zone(FriendMeeting::LOCAL_TIME_ZONE).iso8601
    }
  end
end
