# frozen_string_literal: true

# Takes two people who are no longer friends off each other's future
# meetings. When the owner sent invitations, a job updates the provider
# events, and the provider sends the removed person a cancellation.
#
# Friendship calls it when an accepted friendship is destroyed. An expired
# friendship must call it too.
class FriendMeetingAttendeeRemover < ApplicationService
  def initialize(user_id, other_user_id)
    @user_id       = user_id
    @other_user_id = other_user_id
  end

  def call
    [ [ @user_id, @other_user_id ], [ @other_user_id, @user_id ] ].each do |owner_id, attendee_id|
      remove(owner_id, attendee_id)
    end
  end

  private

  def remove(owner_id, attendee_id)
    meetings = FriendMeeting.live.not_ended.where(user_id: owner_id)
                            .where(id: FriendMeetingAttendee.where(user_id: attendee_id).select(:friend_meeting_id))

    meetings.find_each do |meeting|
      meeting.friend_meeting_attendees.where(user_id: attendee_id).delete_all
      FriendMeetingUpdateJob.perform_later(meeting) if meeting.invite_friends?
    end
  end
end
