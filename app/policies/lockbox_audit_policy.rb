# frozen_string_literal: true

class LockboxAuditPolicy < ApplicationPolicy
  # Only admins+ can list audit logs
  def index?
    admin?
  end

  # Only admins+ can view audit log details
  def show?
    admin?
  end

  # Audit logs are system-generated only
  def create?
    false
  end

  # Audit logs are immutable
  def update?
    false
  end

  # Only super_admins+ can delete audit logs (destructive, for cleanup)
  def destroy?
    super_admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user&.admin_access?
        scope.all
      else
        scope.none
      end
    end

  end

end
