# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  # Admins+ can list all users for management
  def index?
    admin?
  end

  # Users can view their own profile, admins+ can view others for support
  def show?
    record == user || admin?
  end

  # Admins+ can create new users
  def create?
    admin?
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

  # Super_admins+ can refresh OAuth credentials
  def refresh_oauth_credential?
    super_admin?
  end

  # Super_admins+ can toggle support flags (env_switcher, debug_mode)
  def toggle_support_flag?
    super_admin?
  end

  # Super_admins+ can force calendar sync for users
  def force_calendar_sync?
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
