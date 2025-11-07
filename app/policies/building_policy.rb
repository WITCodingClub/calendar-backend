# frozen_string_literal: true

class BuildingPolicy < ApplicationPolicy
  # Everyone can list buildings
  def index?
    true
  end

  # Everyone can view building details
  def show?
    true
  end

  # Admins+ can create buildings
  def create?
    admin?
  end

  # Admins+ can update buildings
  def update?
    admin?
  end

  # Only super_admins+ can delete buildings (destructive)
  def destroy?
    super_admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end
end
