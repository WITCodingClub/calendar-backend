# frozen_string_literal: true

# == Schema Information
#
# Table name: friendships
#
#  id                   :bigint           not null, primary key
#  addressee_visibility :integer          default(0), not null
#  requester_visibility :integer          default(0), not null
#  status               :integer          default(0), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  addressee_id         :bigint           not null
#  requester_id         :bigint           not null
#
# Indexes
#
#  index_friendships_on_addressee_id                   (addressee_id)
#  index_friendships_on_addressee_id_and_status        (addressee_id,status)
#  index_friendships_on_requester_id                   (requester_id)
#  index_friendships_on_requester_id_and_addressee_id  (requester_id,addressee_id) UNIQUE
#  index_friendships_on_requester_id_and_status        (requester_id,status)
#  index_friendships_on_unordered_pair                 (LEAST(requester_id, addressee_id), GREATEST(requester_id, addressee_id)) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (addressee_id => users.id)
#  fk_rails_...  (requester_id => users.id)
#
class Friendship < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :frn, min_hash_length: 10

  belongs_to :requester, class_name: "User"
  belongs_to :addressee, class_name: "User"

  # How much of a user's own schedule the other side of the friendship can see.
  # "full" sends the course list. "availability_only" sends only busy blocks.
  # Each side sets the level for its own schedule, so the two can differ.
  VISIBILITIES = { full: 0, availability_only: 1 }.freeze

  enum :status, { pending: 0, accepted: 1 }, default: :pending
  enum :requester_visibility, VISIBILITIES, default: :full, prefix: :requester
  enum :addressee_visibility, VISIBILITIES, default: :full, prefix: :addressee

  validates :requester_id, uniqueness: { scope: :addressee_id, message: "friendship already exists" }
  validate :cannot_friend_self
  validate :no_reverse_friendship_exists, on: :create

  scope :involving,      ->(user) { where(requester: user).or(where(addressee: user)) }
  scope :pending_for,    ->(user) { pending.where(addressee: user) }
  scope :outgoing_from,  ->(user) { pending.where(requester: user) }
  scope :accepted_for,   ->(user) { accepted.involving(user) }
  scope :between,        lambda { |user, other|
    where(requester: user, addressee: other).or(where(requester: other, addressee: user))
  }

  after_create_commit :email_addressee_about_request, if: :pending?
  # Ex-friends come off each other's future meetings.
  after_destroy_commit :remove_from_friend_meetings, if: :accepted?

  def friend_for(user)
    requester_id == user.id ? addressee : requester
  end

  def requester?(user) = requester_id == user.id
  def addressee?(user) = addressee_id == user.id

  # The level that +user+ set for their own schedule toward the other side.
  def visibility_set_by(user)
    requester?(user) ? requester_visibility : addressee_visibility
  end

  # Sets the level for +user+'s own schedule. Raises ArgumentError for a level
  # that is not in VISIBILITIES.
  def update_visibility_for!(user, level)
    raise ArgumentError, "unknown visibility: #{level.inspect}" unless VISIBILITIES.key?(level.to_s.to_sym)

    column = requester?(user) ? :requester_visibility : :addressee_visibility
    update!(column => level.to_s)
  end

  # True when +viewer+ can see the course list of the other side. The other
  # side's own setting decides, not the viewer's.
  def full_schedule_visible_to?(viewer)
    visibility_set_by(friend_for(viewer)) == "full"
  end

  private

  # Admins can create an already-accepted friendship, so only a pending row is a
  # real request that the addressee has to answer.
  def email_addressee_about_request
    FriendshipMailer.request_received(self).deliver_later
  end

  def remove_from_friend_meetings
    FriendMeetingAttendeeRemover.call(requester_id, addressee_id)
  end

  def cannot_friend_self
    errors.add(:addressee, "cannot be yourself") if requester_id == addressee_id
  end

  def no_reverse_friendship_exists
    return unless Friendship.exists?(requester_id: addressee_id, addressee_id: requester_id)

    errors.add(:base, "A friendship request already exists between these users")
  end
end
