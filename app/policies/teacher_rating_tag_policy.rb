# frozen_string_literal: true

class TeacherRatingTagPolicy < ApplicationPolicy
  # Everyone can list teacher rating tags
  def index?
    true
  end

  # Everyone can view teacher rating tag details
  def show?
    true
  end

  # Admins+ can create teacher rating tags
  def create?
    admin?
  end

  # Admins+ can update teacher rating tags
  def update?
    admin?
  end

  # Only super_admins+ can delete teacher rating tags (destructive)
  def destroy?
    super_admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end

  end

end
