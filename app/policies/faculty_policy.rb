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

  # Super_admins+ can search Rate My Professor for faculty (view-only admins cannot)
  def search_rmp?
    super_admin?
  end

  # Super_admins+ can assign RMP IDs to faculty (view-only admins cannot)
  def assign_rmp_id?
    super_admin?
  end

  # Super_admins+ can auto-fill RMP IDs for faculty (view-only admins cannot)
  def auto_fill_rmp_id?
    super_admin?
  end

  # Super_admins+ can batch auto-fill RMP IDs (view-only admins cannot)
  def batch_auto_fill?
    super_admin?
  end

  # Admins+ can view faculty missing RMP IDs (view-only admins can VIEW but not fill)
  def missing_rmp_ids?
    admin?
  end

  # Super_admins+ can trigger directory sync
  def sync_directory?
    super_admin?
  end

  # Admins+ can view directory sync status
  def directory_status?
    admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end

  end

end
