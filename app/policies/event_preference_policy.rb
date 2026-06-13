# frozen_string_literal: true

class EventPreferencePolicy < ApplicationPolicy
  def index?   = admin?
  def show?    = owner_of_record? || admin?
  def create?  = owner_of_record? || super_admin?
  def update?  = owner_of_record? || super_admin?
  def destroy? = owner_of_record? || can_perform_destructive_action?

  class Scope < ApplicationPolicy::Scope
    def resolve
      user&.admin_access? ? scope.all : scope.where(user_id: user&.id)
    end
  end
end
