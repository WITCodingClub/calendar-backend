# frozen_string_literal: true

module FriendMeetings
  # Starts FriendMeetings::RemoveJob again for each meeting that its owner
  # cancelled more than an hour ago and that still exists, for example after
  # the job ran out of retries. A meeting whose token the provider refused
  # waits: a reconnect finishes it.
  class RemovalSweepJob < ApplicationJob
    queue_as :low

    GRACE = 1.hour

    def perform
      refused = FriendMeetingPublication.where(last_error: FriendMeetings::Publisher::AUTH_ERRORS.map(&:name))

      FriendMeeting.where(cancelled_at: ...GRACE.ago).where.not(id: refused.select(:friend_meeting_id)).find_each do |meeting|
        FriendMeetings::RemoveJob.perform_later(meeting)
      end
    end
  end
end
