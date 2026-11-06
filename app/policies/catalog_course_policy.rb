# frozen_string_literal: true

# The course catalog is public: GET /api/v1/catalog/courses needs no token.
# The dashboard shows it to every signed-in user (#797).
class CatalogCoursePolicy < ApplicationPolicy
  def index?   = user.present?
  def show?    = user.present?
  def create?  = admin?
  def update?  = admin?
  def destroy? = super_admin?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.all
  end
end
