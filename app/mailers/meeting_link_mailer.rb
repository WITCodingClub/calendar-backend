# frozen_string_literal: true

# Tells the guest of a one-time meeting link that the meeting is booked.
#
# An owner with a Google or Microsoft calendar also sends the guest a calendar
# invitation. An owner who uses only the ICS feed sends none, so this email is
# the one message that every guest gets.
class MeetingLinkMailer < ApplicationMailer
  def booked(link)
    @meeting  = link.friend_meeting
    @owner    = link.user
    @starts   = @meeting.local_start
    @ends     = @meeting.end_time.in_time_zone(FriendMeeting::LOCAL_TIME_ZONE)
    @invited  = FriendMeetings::Publisher.new(@owner).calendar_providers.any?

    mail(
      to:       @meeting.guest_email,
      reply_to: @owner.email,
      subject:  "Your meeting with #{@owner.full_name} is booked"
    )
  end
end
