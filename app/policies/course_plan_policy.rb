# frozen_string_literal: true

class CoursePlanPolicy < ApplicationPolicy
  def show?
    owner_of_record? || admin?
  end

  def create?
    true # Any authenticated user can create course plans
  end

  def update?
    owner_of_record? || admin?
  end

  def destroy?
    owner_of_record? || can_perform_destructive_action?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user&.admin_access?
        scope.all
      else
        scope.where(user: user)
      end
    end

  end

end
