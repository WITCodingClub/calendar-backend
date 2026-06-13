# frozen_string_literal: true

class SecurityEventPolicy < ApplicationPolicy
  def index?  = admin?
  def show?   = owner_of_record? || admin?
  def create? = false
  def update? = false
  def destroy? = can_perform_destructive_action?

  class Scope < ApplicationPolicy::Scope
    def resolve
      user&.admin_access? ? scope.all : scope.where(user_id: user&.id)
    end
  end
end
