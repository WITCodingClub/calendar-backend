# frozen_string_literal: true

# Only the owner can change a group. A group is private to the owner until the
# owner shares it. A shared group shows to its members, read only, and each
# member sets their own status in it. Admins get no extra access, because a
# group is personal data about the owner's friends.
class FriendGroupPolicy < ApplicationPolicy
  def index?  = user.present?
  def create? = owner_of_record?

  def show?    = owner_of_record?
  def update?  = owner_of_record?
  def destroy? = owner_of_record?

  # Adding and removing members changes the group, so it needs the same check.
  def manage_members? = owner_of_record?

  # The read-only view of a group that someone shared with the user, with any
  # status, so a member can find a hidden group again or opt back in.
  def show_shared? = shared_membership.present?

  # The member's own status: active, hidden, or opted out.
  def update_membership? = shared_membership.present?

  # The busy times of everyone in the group: for the owner and, when the group
  # is shared, for each member who did not opt out.
  def view_busy_blocks?
    owner_of_record? || (shared_membership.present? && !shared_membership.opted_out?)
  end

  class Scope < ApplicationPolicy::Scope
    # An expired group is gone for its owner too, so its id finds nothing.
    def resolve
      return scope.none unless user

      scope.where(user: user).unexpired
    end
  end

  # The groups that other owners shared with the user, with any member status.
  # Use it with policy_scope(FriendGroup, policy_scope_class: FriendGroupPolicy::SharedScope).
  class SharedScope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user

      scope.shared_with(user).unexpired
    end
  end

  private

  # The user's membership while the group is shared and not expired, else nil.
  def shared_membership
    return @shared_membership if defined?(@shared_membership)

    @shared_membership = (record.membership_for(user) if user && record.shared? && !record.expired?)
  end
end
