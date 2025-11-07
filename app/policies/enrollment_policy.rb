# frozen_string_literal: true

class EnrollmentPolicy < ApplicationPolicy
  # Admins can list enrollments for support
  def index?
    admin?
  end

  # Users can view their own enrollments, admins+ can view all for support
  def show?
    owner_of_record? || admin?
  end

  # Users can create their own enrollments, super_admins+ can create for others
  def create?
    owner_of_record? || super_admin?
  end

  # Users can update their own enrollments, super_admins+ can update others
  def update?
    owner_of_record? || super_admin?
  end

  # Users can delete their own enrollments, but super_admins cannot delete owners' enrollments
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
