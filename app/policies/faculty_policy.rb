# frozen_string_literal: true

class FacultyPolicy < ApplicationPolicy
  # Everyone can list faculty
  def index?
    true
  end

  # Everyone can view faculty details
  def show?
    true
  end

  # Admins+ can create faculty records
  def create?
    admin?
  end

  # Admins+ can update faculty records
  def update?
    admin?
  end

  # Only super_admins+ can delete faculty records (destructive)
  def destroy?
    super_admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end
end
