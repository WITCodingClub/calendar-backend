# frozen_string_literal: true

class MeetingTimePolicy < ApplicationPolicy
  # Everyone can list meeting times
  def index?
    true
  end

  # Everyone can view meeting time details
  def show?
    true
  end

  # Admins+ can create meeting times
  def create?
    admin?
  end

  # Admins+ can update meeting times
  def update?
    admin?
  end

  # Only super_admins+ can delete meeting times (destructive)
  def destroy?
    super_admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end

  end

end
