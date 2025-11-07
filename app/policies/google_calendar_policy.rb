# frozen_string_literal: true

class GoogleCalendarPolicy < ApplicationPolicy
  # Admins can list all calendars for support
  def index?
    admin?
  end

  # Users can view their own calendars, admins+ can view all for support
  def show?
    owner_of_record_through?(:oauth_credential) || admin?
  end

  # Users can create their own calendars, super_admins+ can create for others
  def create?
    owner_of_record_through?(:oauth_credential) || super_admin?
  end

  # Users can update their own calendars, super_admins+ can update others
  def update?
    owner_of_record_through?(:oauth_credential) || super_admin?
  end

  # Users can delete their own calendars, but super_admins cannot delete owners' calendars
  def destroy?
    owner_of_record_through?(:oauth_credential) || can_perform_destructive_action?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user&.admin_access?
        scope.all
      else
        scope.joins(:oauth_credential).where(oauth_credentials: { user_id: user&.id })
      end
    end
  end
end
