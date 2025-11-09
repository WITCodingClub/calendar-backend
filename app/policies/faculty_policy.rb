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

  # Admins+ can search Rate My Professor for faculty
  def search_rmp?
    admin?
  end

  # Admins+ can assign RMP IDs to faculty
  def assign_rmp_id?
    admin?
  end

  # Admins+ can auto-fill RMP IDs for faculty
  def auto_fill_rmp_id?
    admin?
  end

  # Admins+ can batch auto-fill RMP IDs
  def batch_auto_fill?
    admin?
  end

  # Everyone can view faculty missing RMP IDs (uses policy_scope)
  def missing_rmp_ids?
    true
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end

  end

end
