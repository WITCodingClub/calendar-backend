# frozen_string_literal: true

class RmpRatingPolicy < ApplicationPolicy
  # Everyone can list RMP ratings
  def index?
    true
  end

  # Everyone can view RMP rating details
  def show?
    true
  end

  # Admins+ can create RMP ratings (synced from RMP API)
  def create?
    admin?
  end

  # Admins+ can update RMP ratings
  def update?
    admin?
  end

  # Only super_admins+ can delete RMP ratings (destructive)
  def destroy?
    super_admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end
end
