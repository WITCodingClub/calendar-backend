# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  # Admins+ can list all users for management
  def index?
    admin?
  end

  # Users can view their own profile, super_admins+ can view others
  # View-only admins CANNOT view individual user details
  def show?
    record == user || super_admin?
  end

  # Super_admins+ can create new users (admins cannot)
  def create?
    super_admin?
  end

  # Users can update their own profile, super_admins+ can modify others
  def update?
    record == user || super_admin?
  end

  # Users can delete their own account, super_admins+ can delete others
  # (but super_admins cannot delete owners)
  def destroy?
    record == user || can_perform_destructive_action?
  end

  # Super_admins+ can revoke OAuth credentials (admins cannot)
  def revoke_oauth_credential?
    super_admin?
  end

  # Super_admins+ can manage beta tester status (admins cannot)
  def enable_beta?
    super_admin?
  end

  # Super_admins+ can manage beta tester status (admins cannot)
  def disable_beta?
    super_admin?
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
