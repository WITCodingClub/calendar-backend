# frozen_string_literal: true

# Groups are private: only the owner can see or change a group. Admins get no
# extra access, because a group is personal data about the owner's friends.
class FriendGroupPolicy < ApplicationPolicy
  def index?  = user.present?
  def create? = owner_of_record?

  def show?    = owner_of_record?
  def update?  = owner_of_record?
  def destroy? = owner_of_record?

  # Adding and removing members changes the group, so it needs the same check.
  def manage_members? = owner_of_record?

  class Scope < ApplicationPolicy::Scope
    # An expired group is gone for its owner too, so its id finds nothing.
    def resolve
      return scope.none unless user

      scope.where(user: user).unexpired
    end
  end
end
