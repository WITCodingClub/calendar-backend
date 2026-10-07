# frozen_string_literal: true

# == Schema Information
#
# Table name: friend_groups
#
#  id         :bigint           not null, primary key
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_friend_groups_on_user_id_and_lower_name  (user_id, lower((name)::text)) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
# A named group of friends, for example "study group" or "roommates". Only the
# owner sees a group. The friends in it do not know about it.
class FriendGroup < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :fgr

  NAME_MAX_LENGTH = 50

  belongs_to :user
  has_many :memberships, class_name: "FriendGroupMembership", dependent: :destroy, inverse_of: :friend_group
  has_many :friendships, through: :memberships

  normalizes :name, with: ->(name) { name.squish }

  validates :name, presence: true, length: { maximum: NAME_MAX_LENGTH },
                   uniqueness: { scope: :user_id, case_sensitive: false }

  # The API routes and the dashboard UI for groups are off until the privacy
  # policy update. Flipper matches the user on "User;<id>".
  def self.enabled_for?(user)
    user.present? && Flipper.enabled?(FlipperFlags::FRIEND_GROUPS, user)
  end

  # Returns { friend user id => [groups] } for every group the user owns, in two
  # queries, so a friends list can show each friend's groups without one query
  # per friend.
  def self.by_friend_id_for(user)
    memberships = FriendGroupMembership.joins(:friend_group)
                                       .where(friend_groups: { user_id: user.id })
                                       .includes(:friend_group, :friendship)
                                       .order("friend_groups.name")

    memberships.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |membership, groups|
      groups[membership.friendship.friend_id_for(user)] << membership.friend_group
    end
  end

  # The friend users in the group. Preload memberships: { friendship: [:requester, :addressee] }
  # to read this for many groups without a query per group.
  def members
    memberships.map { |membership| membership.friendship.friend_for(user) }
               .sort_by { |friend| friend.full_name.downcase }
  end
end
