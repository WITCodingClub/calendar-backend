# frozen_string_literal: true

class CoursePolicy < ApplicationPolicy
  # Everyone can list courses
  def index?
    true
  end

  # Everyone can view course details
  def show?
    true
  end

  # Admins+ can create courses
  def create?
    admin?
  end

  # Admins+ can update courses
  def update?
    admin?
  end

  # Only super_admins+ can delete courses (destructive)
  def destroy?
    super_admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end
end
