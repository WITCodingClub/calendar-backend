# frozen_string_literal: true

class Friendship < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :frn, min_hash_length: 10

  belongs_to :requester, class_name: "User"
  belongs_to :addressee, class_name: "User"

  enum :status, { pending: 0, accepted: 1 }, default: :pending

  validates :requester_id, uniqueness: { scope: :addressee_id, message: "friendship already exists" }
  validate :cannot_friend_self
  validate :no_reverse_friendship_exists, on: :create

  scope :involving,      ->(user) { where(requester: user).or(where(addressee: user)) }
  scope :pending_for,    ->(user) { pending.where(addressee: user) }
  scope :outgoing_from,  ->(user) { pending.where(requester: user) }
  scope :accepted_for,   ->(user) { accepted.involving(user) }

  def friend_for(user)
    requester_id == user.id ? addressee : requester
  end

  def requester?(user) = requester_id == user.id
  def addressee?(user) = addressee_id == user.id

  private

  def cannot_friend_self
    errors.add(:addressee, "cannot be yourself") if requester_id == addressee_id
  end

  def no_reverse_friendship_exists
    return unless Friendship.exists?(requester_id: addressee_id, addressee_id: requester_id)

    errors.add(:base, "A friendship request already exists between these users")
  end
end
