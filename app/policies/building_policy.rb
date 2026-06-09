# frozen_string_literal: true

class BuildingPolicy < ApplicationPolicy
  def index?             = admin?
  def sync?              = admin?
  def apply_formal_name? = admin?
  def apply_all?         = super_admin?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.all
  end
end
