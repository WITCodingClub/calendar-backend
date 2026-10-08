# frozen_string_literal: true

# Starts FriendMeetingRemoveJob again for each meeting that its owner
# cancelled more than an hour ago and that still exists, for example after
# the job ran out of retries. A meeting whose token the provider refused
# waits: a reconnect finishes it.
class FriendMeetingRemovalSweepJob < ApplicationJob
  queue_as :low

  GRACE = 1.hour

  def perform
    refused = FriendMeetingPublication.where(last_error: FriendMeetingPublisher::AUTH_ERRORS.map(&:name))

    FriendMeeting.where(cancelled_at: ...GRACE.ago).where.not(id: refused.select(:friend_meeting_id)).find_each do |meeting|
      FriendMeetingRemoveJob.perform_later(meeting)
    end
  end
end
