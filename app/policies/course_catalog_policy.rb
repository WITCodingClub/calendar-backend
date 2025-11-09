# frozen_string_literal: true

# Policy for course catalog admin utility
# This is a headless policy (no record) for authorizing admin utility actions
class CourseCatalogPolicy < ApplicationPolicy
  def index?
    # Any admin level access can view the page
    admin?
  end

  def fetch?
    # Any admin level access can fetch the course catalog
    admin?
  end

  def process?
    # Only super_admin and above can process courses into the database
    super_admin?
  end
end
