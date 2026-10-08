# frozen_string_literal: true

class FriendMeetingPolicy < ApplicationPolicy
  # Any signed-in person can make a meeting. FriendMeetingCreator checks that
  # each invited person is an accepted friend.
  def create? = user.present?

  # The list route reads only the person's own and invited meetings.
  def index? = user.present?

  # The owner, or a friend that the owner invited.
  def show? = !record.cancelled? && (record.owned_by?(user) || record.invited?(user))

  # Only the owner changes or deletes a meeting.
  def update?  = !record.cancelled? && record.owned_by?(user)
  def destroy? = update?

  # Only an invited friend leaves a meeting. The owner deletes it instead.
  def leave? = !record.cancelled? && record.invited?(user)

  class Scope < ApplicationPolicy::Scope
    # The person's own meetings, and the ones that invited them.
    def resolve
      return scope.none unless user

      scope.live.where(user_id: user.id).or(scope.live.inviting(user))
    end
  end
end
