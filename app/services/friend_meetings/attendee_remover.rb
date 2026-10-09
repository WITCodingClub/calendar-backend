# frozen_string_literal: true

module FriendMeetings
  # Takes two people who are no longer friends off each other's meetings, past
  # ones too, so neither can read the other's meetings any more. For a future
  # meeting whose owner sent invitations, a job updates the provider events,
  # and the provider sends the removed person a cancellation.
  #
  # Friendship calls it when an accepted friendship is destroyed. An expired
  # friendship must call it too.
  class AttendeeRemover < ApplicationService
    def initialize(user_id, other_user_id)
      @user_id       = user_id
      @other_user_id = other_user_id
    end

    # Both directions in one set of queries, whatever the number of meetings.
    def call
      rows = rows_for(@user_id, @other_user_id).or(rows_for(@other_user_id, @user_id))
      ids, meeting_ids = rows.pluck(:id, :friend_meeting_id).transpose
      return if ids.nil?

      meetings = FriendMeeting.live.not_ended.where(invite_friends: true, id: meeting_ids).to_a

      FriendMeetingAttendee.where(id: ids).delete_all
      meetings.each { |meeting| FriendMeetings::UpdateJob.perform_later(meeting) }
    end

    private

    # The rows that put +attendee_id+ on a meeting that +owner_id+ owns.
    def rows_for(owner_id, attendee_id)
      FriendMeetingAttendee.where(user_id: attendee_id, friend_meeting_id: FriendMeeting.where(user_id: owner_id).select(:id))
    end
  end
end
