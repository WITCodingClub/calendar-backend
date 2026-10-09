# frozen_string_literal: true

module CourseCalendars
  class IcsFeed
    # Meetings that the person made from a suggested time and sent to the feed.
    # A feed cannot send invitations, so the friends are listed as attendees
    # only when the person asked to invite them. Most people have no meetings,
    # so they pay for one indexed query.
    class FriendMeetingEvents
      def initialize(user)
        @user = user
      end

      def append_to(cal)
        return unless @user.friend_meetings.exists?

        meetings = @user.friend_meetings.live.not_ended
                        .where(id: FriendMeetingPublication.provider_ics.select(:friend_meeting_id))
        meetings.includes(:attendees).find_each do |meeting|
          cal.event { |e| fill(e, meeting) }
        end
      end

      private

      def fill(e, meeting)
        e.dtstart  = Icalendar::Values::DateTime.new(meeting.local_start, tzid: TZID)
        e.dtend    = Icalendar::Values::DateTime.new(meeting.end_time.in_time_zone(TZID), tzid: TZID)
        e.summary  = meeting.title
        e.location = meeting.location if meeting.location.present?
        e.rrule    = meeting.recurrence.first.delete_prefix("RRULE:") if meeting.weekly?
        e.uid      = "friend-meeting-#{meeting.public_id}@calendar-util.wit.edu"
        # From updated_at, not the request time, so an unchanged meeting gives
        # the same feed body (and ETag) on every request.
        changed_at      = meeting.updated_at.in_time_zone(TZID)
        e.dtstamp       = Icalendar::Values::DateTime.new(changed_at, tzid: TZID)
        e.last_modified = Icalendar::Values::DateTime.new(changed_at, tzid: TZID)
        e.sequence = (meeting.updated_at.to_i / 60)

        meeting.invitees.each do |friend|
          e.append_attendee(Icalendar::Values::CalAddress.new("mailto:#{friend.email}", cn: friend.full_name))
        end
      end
    end
  end
end
