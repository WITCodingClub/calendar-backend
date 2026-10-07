# frozen_string_literal: true

class FriendshipPolicy < ApplicationPolicy
  def index?    = true
  def requests? = true

  def create?   = user && record.requester_id == user.id
  def accept?   = participant_as?(:addressee) && record.pending? && !record.expired?
  def decline?  = participant_as?(:addressee) && record.pending?
  def cancel?   = participant_as?(:requester) && record.pending?
  def destroy?  = user && (record.requester_id == user.id || record.addressee_id == user.id)

  # Either side can extend the date, shorten it, or make the friendship
  # permanent, while the friendship or request has not expired.
  def update_expiry?
    return false unless user && !record.expired?

    record.requester_id == user.id || record.addressee_id == user.id
  end

  # An expired friendship grants nothing, even before the cleanup job deletes
  # the row.
  def view_schedule?
    return false unless user && record.accepted? && !record.expired?

    record.requester_id == user.id || record.addressee_id == user.id
  end

  # Busy blocks hold no course data, so every accepted friend can read them.
  def view_availability? = view_schedule?

  # The course list needs the other side to share its full schedule.
  def view_full_schedule? = view_schedule? && record.full_schedule_visible_to?(user)

  def update_visibility? = view_schedule?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.unexpired.involving(user)
  end

  private

  def participant_as?(role)
    return false unless user

    role == :addressee ? record.addressee_id == user.id : record.requester_id == user.id
  end
end
