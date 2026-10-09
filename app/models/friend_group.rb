# frozen_string_literal: true

# == Schema Information
#
# Table name: friend_groups
#
#  id         :bigint           not null, primary key
#  expires_at :datetime
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_friend_groups_on_expires_at              (expires_at) WHERE (expires_at IS NOT NULL)
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

  # A group with an end date in the past is gone for the owner, even before
  # FriendGroups::RemoveExpiredJob deletes the row. FriendGroupPolicy::Scope
  # reads only unexpired groups. The friendships in the group stay.
  scope :unexpired, -> { where("friend_groups.expires_at IS NULL OR friend_groups.expires_at > ?", Time.current) }
  scope :expired,   -> { where(expires_at: ..Time.current) }

  normalizes :name, with: ->(name) { name.squish }

  # An expired group with the same name blocks a new one through the unique
  # name index until the cleanup job runs, so remove it first.
  before_validation :remove_expired_namesake, on: :create

  validates :name, presence: true, length: { maximum: NAME_MAX_LENGTH },
                   uniqueness: { scope: :user_id, case_sensitive: false }
  validate :expires_at_in_future, if: :will_save_change_to_expires_at?

  # The API routes and the dashboard UI for groups are off until the privacy
  # policy update. Flipper matches the user on "User;<id>".
  def self.enabled_for?(user)
    user.present? && Flipper.enabled?(FeatureFlags::FRIEND_GROUPS, user)
  end

  # Returns { friend user id => [groups] } for every group the user owns, in two
  # queries, so a friends list can show each friend's groups without one query
  # per friend.
  def self.by_friend_id_for(user)
    memberships = FriendGroupMembership.joins(:friend_group)
                                       .where(friend_groups: { user_id: user.id })
                                       .where(friendship_id: user.accepted_friendships.select(:id))
                                       .merge(FriendGroup.unexpired)
                                       .includes(:friend_group, :friendship)
                                       .order("friend_groups.name")

    memberships.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |membership, groups|
      groups[membership.friendship.friend_id_for(user)] << membership.friend_group
    end
  end

  # The friend users in the group. Preload memberships: { friendship: [:requester, :addressee] }
  # to read this for many groups without a query per group. A membership whose
  # friendship is no longer an accepted friendship of the owner is left out.
  def members
    live = user.accepted_friendship_ids
    memberships.select { |membership| live.include?(membership.friendship_id) }
               .map { |membership| membership.friendship.friend_for(user) }
               .sort_by { |friend| friend.full_name.downcase }
  end

  # Raised when some member ids are not accepted friends of the owner.
  class UnknownFriends < StandardError
    attr_reader :ids

    def initialize(ids)
      @ids = ids
      super("Not accepted friends: #{ids.join(', ')}")
    end
  end

  # Saves the group. When friend_ids is not nil, it also REPLACES the members
  # with those friends (user public ids). All of it happens in one transaction.
  # Any id that is not an accepted friend raises UnknownFriends before anything
  # changes. An invalid name raises RecordInvalid and rolls everything back.
  def save_with_members!(attributes = {}, friend_ids: nil)
    transaction do
      friendships = friendships_for_public_ids(friend_ids) unless friend_ids.nil?
      assign_attributes(attributes)
      save!
      replace_memberships(friendships) unless friendships.nil?
    end
    self
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  private

  def remove_expired_namesake
    return if user_id.nil? || name.blank?

    FriendGroup.expired.where(user_id: user_id).where("lower(name) = ?", name.downcase).delete_all
  end

  # nil means the group does not end. A date in the past would remove it at once.
  def expires_at_in_future
    return if expires_at.nil?

    errors.add(:expires_at, "must be in the future") if expires_at <= Time.current
  end

  # Two queries plus one preload, for any number of ids.
  def friendships_for_public_ids(friend_ids)
    wanted = Array(friend_ids).map(&:to_s).uniq
    return [] if wanted.empty?

    by_public_id = user.accepted_friendships.includes(:requester, :addressee)
                       .index_by { |friendship| friendship.friend_for(user).public_id }
    unknown = wanted - by_public_id.keys
    raise UnknownFriends, unknown if unknown.any?

    by_public_id.values_at(*wanted)
  end

  # The friendships come from accepted_friendships, so the membership
  # validation would pass. insert_all skips it to avoid one query per row.
  def replace_memberships(friendships)
    wanted   = friendships.map(&:id)
    existing = memberships.pluck(:friendship_id)

    memberships.where(friendship_id: existing - wanted).delete_all
    added = wanted - existing
    memberships.klass.insert_all(added.map { |id| { friend_group_id: self.id, friendship_id: id } }) if added.any?
    memberships.reset
  end
end
