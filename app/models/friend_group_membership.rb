# frozen_string_literal: true

# == Schema Information
#
# Table name: friend_group_memberships
#
#  id              :bigint           not null, primary key
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  friend_group_id :bigint           not null
#  friendship_id   :bigint           not null
#
# Indexes
#
#  index_friend_group_memberships_on_friendship_id         (friendship_id)
#  index_friend_group_memberships_on_group_and_friendship  (friend_group_id,friendship_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (friend_group_id => friend_groups.id) ON DELETE => cascade
#  fk_rails_...  (friendship_id => friendships.id) ON DELETE => cascade
#
# Puts one friend in one FriendGroup. It points at the friendship, not at the
# friend's user row, so removing the friendship removes the membership too.
class FriendGroupMembership < ApplicationRecord
  belongs_to :friend_group
  belongs_to :friendship

  validates :friendship_id, uniqueness: { scope: :friend_group_id, message: "is already in this group" }
  validate :friendship_belongs_to_group_owner

  private

  def friendship_belongs_to_group_owner
    return if friend_group.nil? || friendship.nil?
    return if friendship.accepted? && friendship.involves?(friend_group.user_id)

    errors.add(:friendship, "must be an accepted friendship of the group owner")
  end
end
