# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  def index?   = admin?
  def show?    = record == user || admin?
  def create?  = admin?
  def update?  = record == user || super_admin?
  def destroy? = can_perform_destructive_action?

  def revoke_oauth_credential?   = super_admin?
  def refresh_oauth_credential?  = super_admin?
  def force_calendar_sync?       = super_admin?
  def manage_friendships?        = super_admin?

  def view_user_details?         = show?
  def view_oauth_credentials?    = admin?
  def manage_oauth_credentials?  = super_admin?
  def view_enrollments?          = show?
  def view_calendar_sync_info?   = admin?
  def view_access_level?         = super_admin?
  def edit_access_level?         = super_admin?

  class Scope < ApplicationPolicy::Scope
    def resolve
      user&.admin_access? ? scope.all : scope.where(id: user&.id)
    end
  end
end
