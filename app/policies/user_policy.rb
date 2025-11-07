# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  # Admins can list all users for management
  def index?
    admin?
  end

  # Users can view their own profile, admins+ can view all for support
  def show?
    owner_of_record? || admin?
  end

  # Admins+ can create new users
  def create?
    admin?
  end

  # Users can update their own profile, super_admins+ can modify others
  # (super_admin needed to change access_level)
  def update?
    owner_of_record? || super_admin?
  end

  # Users can delete their own account, but super_admins cannot delete owners
  def destroy?
    owner_of_record? || can_perform_destructive_action?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user&.admin_access?
        scope.all
      else
        scope.where(id: user&.id)
      end
    end
  end
end
