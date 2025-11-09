# frozen_string_literal: true

class SecurityEventPolicy < ApplicationPolicy
  # Admins can list security events for monitoring and support
  def index?
    admin?
  end

  # Users can view their own security events, admins+ can view all for monitoring
  def show?
    owner_of_record? || admin?
  end

  # Security events are created by the system only, not by users
  def create?
    false
  end

  # Security events cannot be manually updated
  def update?
    false
  end

  # Only super_admins+ can delete security events (for cleanup/retention)
  def destroy?
    can_perform_destructive_action?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user&.admin_access?
        # Admins can see all security events for monitoring
        scope.all
      else
        # Users can only see their own security events
        scope.where(user_id: user&.id)
      end
    end
  end
end
