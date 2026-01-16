# frozen_string_literal: true

class FriendshipPolicy < ApplicationPolicy
  # List accepted friends - users can see their own friends
  def index?
    true
  end

  # View friend requests
  def requests?
    true
  end

  # Create a friend request (user must be the requester)
  def create?
    user && record.requester_id == user.id
  end

  # Accept a friend request (only addressee can accept)
  def accept?
    user && record.addressee_id == user.id && record.pending?
  end

  # Decline a friend request (only addressee can decline)
  def decline?
    user && record.addressee_id == user.id && record.pending?
  end

  # Cancel an outgoing request (only requester can cancel)
  def cancel?
    user && record.requester_id == user.id && record.pending?
  end

  # Unfriend (either party can unfriend)
  def destroy?
    user && (record.requester_id == user.id || record.addressee_id == user.id)
  end

  # View a friend's schedule (only if friendship is accepted and user is involved)
  def view_schedule?
    return false unless user && record.accepted?

    record.requester_id == user.id || record.addressee_id == user.id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      # Users can only see friendships they're involved in
      scope.involving(user)
    end

  end

end
