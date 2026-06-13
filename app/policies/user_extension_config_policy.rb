# frozen_string_literal: true

class UserExtensionConfigPolicy < ApplicationPolicy
  def index?
    admin?
  end

  def show?
    owner_of_record? || admin?
  end

  def create?
    owner_of_record? || super_admin?
  end

  def update?
    owner_of_record? || super_admin?
  end

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
