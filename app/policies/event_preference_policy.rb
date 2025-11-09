# frozen_string_literal: true

class EventPreferencePolicy < ApplicationPolicy
  # Admins can list event preferences for support
  def index?
    admin?
  end

  # Users can view their own event preferences, admins+ can view all for support
  def show?
    owner_of_record? || admin?
  end

  # Users can create their own event preferences, super_admins+ can create for others
  def create?
    owner_of_record? || super_admin?
  end

  # Users can update their own event preferences, super_admins+ can update others
  def update?
    owner_of_record? || super_admin?
  end

  # Users can delete their own event preferences, but super_admins cannot delete owners' preferences
  def destroy?
    owner_of_record? || can_perform_destructive_action?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user&.admin_access?
        scope.all
      else
        scope.where(user_id: user&.id)
      end
    end

  end

end
