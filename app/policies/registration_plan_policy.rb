# frozen_string_literal: true

# A student sees and changes only their own registration plans (#995). An
# admin can see a plan, but cannot change it.
class RegistrationPlanPolicy < ApplicationPolicy
  def index?   = user.present?
  def show?    = owner_of_record? || admin?
  def create?  = owner_of_record?
  def update?  = owner_of_record?
  def destroy? = owner_of_record?

  class Scope < ApplicationPolicy::Scope
    def resolve
      user&.admin_access? ? scope.all : scope.where(user_id: user&.id)
    end
  end
end
