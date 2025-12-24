# frozen_string_literal: true

class UniversityCalendarEventPolicy < ApplicationPolicy
  # University events are public read - anyone can view
  def index?
    true
  end

  def show?
    true
  end

  # Only admins can trigger sync
  def sync?
    admin?
  end

  # Only admins can create events (typically done via sync job)
  def create?
    admin?
  end

  # Only admins can update events
  def update?
    admin?
  end

  # Only super_admins can delete events
  def destroy?
    super_admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      # All events are publicly visible
      scope.all
    end

  end

end
