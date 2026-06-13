# frozen_string_literal: true

class RelatedProfessorPolicy < ApplicationPolicy
  def index?  = true
  def show?   = true
  def create? = admin?
  def update? = admin?
  def destroy? = super_admin?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.all
  end
end
