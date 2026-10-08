# frozen_string_literal: true

# Deletes friendships and pending requests whose expiry date has passed.
#
# An expired friendship already grants nothing: Friendship.unexpired hides it
# and FriendshipPolicy#view_schedule? refuses it. This job removes the rows,
# so the two people can send a new request later. delete_all skips the
# after_destroy_commit callback, so the job takes ex-friends off each other's
# meetings itself.
class RemoveExpiredFriendshipsJob < ApplicationJob
  queue_as :low

  def perform
    Friendship.expired.accepted.pluck(:requester_id, :addressee_id).each do |requester_id, addressee_id|
      FriendMeetingAttendeeRemover.call(requester_id, addressee_id)
    end

    removed = Friendship.expired.delete_all

    Rails.logger.info "[RemoveExpiredFriendshipsJob] Removed #{removed} expired friendships"

    { removed: removed }
  end
end
