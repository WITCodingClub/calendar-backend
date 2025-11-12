# frozen_string_literal: true

# Policy for course catalog admin utility
# This is a headless policy (no record) for authorizing admin utility actions
class CourseCatalogPolicy < ApplicationPolicy
  def index?
    # Super_admins+ can view the course catalog page (view-only admins cannot)
    super_admin?
  end

  def fetch?
    # Super_admins+ can fetch the course catalog (view-only admins cannot)
    super_admin?
  end

  def process?
    # Super_admins+ can process courses into the database (view-only admins cannot)
    super_admin?
  end
end
