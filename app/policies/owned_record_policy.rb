# frozen_string_literal: true

# Records that belong to one user. The user and admins read them. The user and
# super admins change them. An owner's record can only be deleted by the user or
# another owner (can_perform_destructive_action?).
class OwnedRecordPolicy < ApplicationPolicy
  def index?   = admin?
  def show?    = owned? || admin?
  def create?  = owned? || super_admin?
  def update?  = owned? || super_admin?
  def destroy? = owned? || can_perform_destructive_action?

  class Scope < ApplicationPolicy::OwnerScope; end

  private

  def owned? = owner_of_record?
end
