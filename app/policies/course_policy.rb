# frozen_string_literal: true

class CoursePolicy < ApplicationPolicy
  def index?   = admin?
  def show?    = admin?
  def create?  = admin?
  def update?  = admin?
  def destroy? = super_admin?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.all
  end
end
