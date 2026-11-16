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
        IcsFeed.set_times(e, meeting.calendar_event)
        e.summary  = meeting.title
        e.location = meeting.location if meeting.location.present?
        e.rrule    = meeting.recurrence.rule if meeting.repeating?
        e.uid      = IcsFeed.uid("friend-meeting-#{meeting.public_id}")
        IcsFeed.set_changed_at(e, meeting.updated_at)

        meeting.invitees.each do |friend|
          e.append_attendee(Icalendar::Values::CalAddress.new("mailto:#{friend.email}", cn: friend.full_name))
        end
      end
    end
  end
end
