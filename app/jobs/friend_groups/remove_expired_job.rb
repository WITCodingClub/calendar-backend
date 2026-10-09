# frozen_string_literal: true

module FriendGroups
  # Deletes friend groups whose end date has passed (#707).
  #
  # An expired group is already hidden: FriendGroupPolicy::Scope reads only
  # unexpired groups. This job removes the rows. The database removes the
  # memberships with them (on_delete: :cascade). The friendships stay.
  class RemoveExpiredJob < ApplicationJob
    queue_as :low

    def perform
      removed = FriendGroup.expired.delete_all

      Rails.logger.info "[FriendGroups::RemoveExpiredJob] Removed #{removed} expired friend groups"

      { removed: removed }
    end
  end
end
