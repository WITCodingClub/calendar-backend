# frozen_string_literal: true

# The admin pages of the degree requirements import (#864). The catalog is
# public, so every admin can read it and start an import of one year.
class CatalogYearPolicy < ApplicationPolicy
  def index?             = admin?
  def show?              = admin?
  def import?            = admin?
  def course_comparison? = admin?
end
