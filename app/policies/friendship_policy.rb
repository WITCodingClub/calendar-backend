# frozen_string_literal: true

class FriendshipPolicy < ApplicationPolicy
  def index?    = true
  def requests? = true

  def create?   = user && record.requester_id == user.id
  def accept?   = user && record.addressee_id == user.id && record.pending?
  def decline?  = user && record.addressee_id == user.id && record.pending?
  def cancel?   = user && record.requester_id == user.id && record.pending?
  def destroy?  = user && (record.requester_id == user.id || record.addressee_id == user.id)

  def view_schedule?
    return false unless user && record.accepted?

    record.requester_id == user.id || record.addressee_id == user.id
  end

  # Busy blocks hold no course data, so every accepted friend can read them.
  def view_availability? = view_schedule?

  # The course list needs the other side to share its full schedule.
  def view_full_schedule? = view_schedule? && record.full_schedule_visible_to?(user)

  def update_visibility? = view_schedule?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.involving(user)
  end
end
