# frozen_string_literal: true

# == Schema Information
#
# Table name: friend_groups
#
#  id         :bigint           not null, primary key
#  color      :string
#  expires_at :datetime
#  name       :string           not null
#  shared     :boolean          default(FALSE), not null
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
# owner sees a group, until the owner shares it. A shared group also shows to
# its members, read only: they see the owner, the other members, and the busy
# times of each one. Only the owner changes a group. Each member can hide the
# group or opt out of it (FriendGroupMembership#status).
class FriendGroup < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :fgr

  NAME_MAX_LENGTH = 50

  belongs_to :user
  has_many :memberships, class_name: "FriendGroupMembership", dependent: :destroy, inverse_of: :friend_group
  has_many :friendships, through: :memberships
  has_many :opt_outs, class_name: "FriendGroupOptOut", dependent: :delete_all, inverse_of: :friend_group

  # A group with an end date in the past is gone for the owner, even before
  # FriendGroups::RemoveExpiredJob deletes the row. FriendGroupPolicy::Scope
  # reads only unexpired groups. The friendships in the group stay.
  scope :unexpired, -> { where("friend_groups.expires_at IS NULL OR friend_groups.expires_at > ?", Time.current) }
  scope :expired,   -> { where(expires_at: ..Time.current) }

  # The shared groups of other owners that hold the user as a member, with any
  # member status. A membership points at a friendship of the owner, so when
  # that friendship is one of the user's accepted friendships, the user is the
  # member.
  scope :shared_with, lambda { |user|
    member_of = FriendGroupMembership.where(friendship_id: user.accepted_friendships.select(:id))
    where(shared: true).where.not(user_id: user.id).where(id: member_of.select(:friend_group_id))
  }

  normalizes :name, with: ->(name) { name.squish }
  # Only "#rrggbb" in any case. The format check rejects every other value,
  # also the legacy palette ids that GoogleCalendar::Colors accepts.
  normalizes :color, with: ->(color) { color.is_a?(String) ? color.strip.downcase : color }

  # An expired group with the same name blocks a new one through the unique
  # name index until the cleanup job runs, so remove it first.
  before_validation :remove_expired_namesake, on: :create

  validates :name, presence: true, length: { maximum: NAME_MAX_LENGTH },
                   uniqueness: { scope: :user_id, case_sensitive: false }
  validates :color, format: { with: GoogleCalendar::Colors::HEX_FORMAT }, allow_nil: true
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

  # { friend user => membership }, sorted by the friend's name. Preload
  # memberships: { friendship: [:requester, :addressee] } to read this for many
  # groups without a query per group. It still runs one query per owner, for
  # the owner's friendships, so a list of shared groups from many owners runs
  # one query per owner. A membership whose friendship is no longer an
  # accepted friendship of the owner is left out.
  def memberships_by_member
    live = user.accepted_friendship_ids
    memberships.select { |membership| live.include?(membership.friendship_id) }
               .index_by { |membership| membership.friendship.friend_for(user) }
               .sort_by { |friend, _| friend.full_name.downcase }
               .to_h
  end

  # Every friend user in the group, also the members who opted out. Only the
  # owner sees this list.
  def members
    memberships_by_member.keys
  end

  # The people that the members of a shared group see: the owner, then each
  # member who did not opt out. A member without the friend_groups flag cannot
  # see the group or opt out, so the other members do not see that member
  # either.
  def shared_people
    visible = memberships_by_member.reject do |friend, membership|
      membership.opted_out? || !FriendGroup.enabled_for?(friend)
    end
    [ user, *visible.keys ]
  end

  # The people whose busy times the viewer reads in this group. The owner is a
  # friend of each member, so the owner sees every member.
  def people_for(viewer)
    viewer.id == user_id ? [ user, *members ] : shared_people
  end

  # The membership of other_user, or nil. The owner has none. It reads the
  # loaded memberships when they are there, so a list of groups runs no query
  # per group.
  def membership_for(other_user)
    return nil if other_user.nil? || other_user.id == user_id

    if memberships.loaded?
      ids = other_user.accepted_friendship_ids
      memberships.to_a.find { |membership| ids.include?(membership.friendship_id) }
    else
      memberships.find_by(friendship_id: other_user.accepted_friendships.select(:id))
    end
  end

  # True when other_user is in the group through an accepted friendship with
  # the owner, with any status.
  def member?(other_user)
    membership_for(other_user).present?
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
    added = friendships.reject { |friendship| existing.include?(friendship.id) }
    if added.any?
      opted_out = opt_outs.pluck(:user_id).to_set
      memberships.klass.insert_all(added.map { |friendship| membership_row(friendship, opted_out) })
    end
    memberships.reset
  end

  # insert_all skips the FriendGroupMembership callbacks, so a row for a friend
  # who opted out before starts as opted_out here.
  def membership_row(friendship, opted_out_user_ids)
    status = opted_out_user_ids.include?(friendship.friend_id_for(user)) ? "opted_out" : "active"

    { friend_group_id: id, friendship_id: friendship.id, status: status }
  end
end
