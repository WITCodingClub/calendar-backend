# frozen_string_literal: true

# == Schema Information
#
# Table name: friend_group_memberships
#
#  id              :bigint           not null, primary key
#  status          :string           default("active"), not null
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
#
# The member sets the status. It matters only while the group is shared:
#
# - active: the member sees the group, and the other members see the member.
# - hidden: the member ignores the group. It leaves the member's own list,
#   but the other members still see the member.
# - opted_out: the member does not see the group, and the other members do
#   not see the member or the member's busy times. The owner still sees the
#   member. A FriendGroupOptOut row keeps the opt-out when the owner removes
#   the member and adds them again.
class FriendGroupMembership < ApplicationRecord
  STATUSES = { active: "active", hidden: "hidden", opted_out: "opted_out" }.freeze

  belongs_to :friend_group
  belongs_to :friendship

  enum :status, STATUSES, default: :active, validate: true

  validates :friendship_id, uniqueness: { scope: :friend_group_id, message: "is already in this group" }
  validate :friendship_belongs_to_group_owner

  before_create :apply_saved_opt_out
  after_save :sync_opt_out, if: :saved_change_to_status?

  # The user in the group: the friend of the owner.
  def member_user_id
    friendship.friend_id_for(friend_group.user)
  end

  private

  def apply_saved_opt_out
    return unless active?

    self.status = :opted_out if FriendGroupOptOut.exists?(friend_group_id: friend_group_id, user_id: member_user_id)
  end

  def sync_opt_out
    opt_out = FriendGroupOptOut.where(friend_group_id: friend_group_id, user_id: member_user_id)
    opted_out? ? opt_out.first_or_create! : opt_out.delete_all
  end

  def friendship_belongs_to_group_owner
    return if friend_group.nil? || friendship.nil?
    return if friend_group.user.accepted_friendships.exists?(id: friendship.id)

    errors.add(:friendship, "must be an accepted friendship of the group owner")
  end
end
