# frozen_string_literal: true

class EnrollmentPolicy < ApplicationPolicy
  def index?   = super_admin?
  def show?    = owner_of_record? || super_admin?
  def create?  = owner_of_record? || super_admin?
  def update?  = owner_of_record? || super_admin?
  def destroy? = owner_of_record? || can_perform_destructive_action?

  class Scope < ApplicationPolicy::Scope
    def resolve
      (user&.super_admin? || user&.owner?) ? scope.all : scope.where(user_id: user&.id)
    end
  end
end
