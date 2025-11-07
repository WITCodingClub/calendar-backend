# frozen_string_literal: true

class UserExtensionConfigPolicy < ApplicationPolicy
  # Admins can list extension configs for support
  def index?
    admin?
  end

  # Users can view their own config, admins+ can view all for support
  def show?
    owner_of_record? || admin?
  end

  # Users can create their own config, super_admins+ can create for others
  def create?
    owner_of_record? || super_admin?
  end

  # Users can update their own config, super_admins+ can update others
  def update?
    owner_of_record? || super_admin?
  end

  # Users can delete their own config, but super_admins cannot delete owners' configs
  def destroy?
    owner_of_record? || can_perform_destructive_action?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user&.admin_access?
        scope.all
      else
        scope.where(user_id: user&.id)
      end
    end
  end
end
