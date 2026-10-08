# frozen_string_literal: true

# Takes two people who are no longer friends off each other's meetings, past
# ones too, so neither can read the other's meetings any more. For a future
# meeting whose owner sent invitations, a job updates the provider events,
# and the provider sends the removed person a cancellation.
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
    rows     = FriendMeetingAttendee.where(user_id: attendee_id, friend_meeting_id: FriendMeeting.where(user_id: owner_id).select(:id))
    meetings = FriendMeeting.live.not_ended.where(invite_friends: true, id: rows.select(:friend_meeting_id)).to_a

    rows.delete_all
    meetings.each { |meeting| FriendMeetingUpdateJob.perform_later(meeting) }
  end
end
