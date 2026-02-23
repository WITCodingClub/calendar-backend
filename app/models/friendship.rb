# frozen_string_literal: true

# == Schema Information
#
# Table name: friendships
# Database name: primary
#
#  id           :bigint           not null, primary key
#  status       :integer          default("pending"), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  addressee_id :bigint           not null
#  requester_id :bigint           not null
#
# Indexes
#
#  index_friendships_on_addressee_id                   (addressee_id)
#  index_friendships_on_addressee_id_and_status        (addressee_id,status)
#  index_friendships_on_requester_id                   (requester_id)
#  index_friendships_on_requester_id_and_addressee_id  (requester_id,addressee_id) UNIQUE
#  index_friendships_on_requester_id_and_status        (requester_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (addressee_id => users.id)
#  fk_rails_...  (requester_id => users.id)
#
class Friendship < ApplicationRecord
  belongs_to :requester, class_name: "User"
  belongs_to :addressee, class_name: "User"

  enum :status, { pending: 0, accepted: 1 }, default: :pending

  validates :requester_id, uniqueness: { scope: :addressee_id, message: "friendship already exists" }
  validate :cannot_friend_self
  validate :no_reverse_friendship_exists, on: :create

  # Scopes
  scope :involving, ->(user) { where(requester: user).or(where(addressee: user)) }
  scope :pending_for, ->(user) { pending.where(addressee: user) }
  scope :outgoing_from, ->(user) { pending.where(requester: user) }
  scope :accepted_for, ->(user) { accepted.involving(user) }

  # Get the friend (the other user in the friendship)
  def friend_for(user)
    requester_id == user.id ? addressee : requester
  end

  # Check if user is the requester (can cancel)
  def requester?(user)
    requester_id == user.id
  end

  # Check if user is the addressee (can accept/decline)
  def addressee?(user)
    addressee_id == user.id
  end

  private

  def cannot_friend_self
    return unless requester_id == addressee_id

    errors.add(:addressee, "cannot be yourself")
  end

  def no_reverse_friendship_exists
    return unless Friendship.exists?(requester_id: addressee_id, addressee_id: requester_id)

    errors.add(:base, "A friendship request already exists between these users")
  end

end
