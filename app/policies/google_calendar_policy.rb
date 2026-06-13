# frozen_string_literal: true

class GoogleCalendarPolicy < ApplicationPolicy
  def index?   = admin?
  def show?    = owner_of_record_through?(:oauth_credential) || admin?
  def create?  = owner_of_record_through?(:oauth_credential) || super_admin?
  def update?  = owner_of_record_through?(:oauth_credential) || super_admin?
  def destroy? = owner_of_record_through?(:oauth_credential) || can_perform_destructive_action?

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
