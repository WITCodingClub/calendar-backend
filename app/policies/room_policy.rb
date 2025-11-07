# frozen_string_literal: true

class RoomPolicy < ApplicationPolicy
  # Everyone can list rooms
  def index?
    true
  end

  # Everyone can view room details
  def show?
    true
  end

  # Admins+ can create rooms
  def create?
    admin?
  end

  # Admins+ can update rooms
  def update?
    admin?
  end

  # Only super_admins+ can delete rooms (destructive)
  def destroy?
    super_admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end
end
