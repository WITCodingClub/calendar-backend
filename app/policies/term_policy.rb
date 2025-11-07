# frozen_string_literal: true

class TermPolicy < ApplicationPolicy
  # Everyone can list terms
  def index?
    true
  end

  # Everyone can view term details
  def show?
    true
  end

  # Admins+ can create terms
  def create?
    admin?
  end

  # Admins+ can update terms
  def update?
    admin?
  end

  # Only super_admins+ can delete terms (destructive)
  def destroy?
    super_admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end
end
