# frozen_string_literal: true

# Deletes friendships and pending requests whose expiry date has passed.
#
# An expired friendship already grants nothing: Friendship.unexpired hides it
# and FriendshipPolicy#view_schedule? refuses it. This job only removes the
# rows, so the two people can send a new request later.
class RemoveExpiredFriendshipsJob < ApplicationJob
  queue_as :low

  def perform
    removed = Friendship.expired.delete_all

    Rails.logger.info "[RemoveExpiredFriendshipsJob] Removed #{removed} expired friendships"

    { removed: removed }
  end
end
