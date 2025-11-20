# frozen_string_literal: true

# Policy for course catalog admin utility
# This is a headless policy (no record) for authorizing admin utility actions
class CourseCatalogPolicy < ApplicationPolicy
  def index?
    # All admins can view the course catalog page
    admin?
  end

  def fetch?
    # All admins can fetch the course catalog
    admin?
  end

  def process?
    # Super_admins+ can process courses into the database (view-only admins cannot)
    super_admin?
  end
end
