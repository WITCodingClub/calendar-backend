# frozen_string_literal: true

class GoogleCalendarEventPolicy < ApplicationPolicy
  def index?   = admin?
  def show?    = owner_through_calendar? || admin?
  def create?  = owner_through_calendar? || super_admin?
  def update?  = owner_through_calendar? || super_admin?
  def destroy? = owner_through_calendar? || can_perform_destructive_action?

  private

  def owner_through_calendar?
    return false unless user && record.respond_to?(:google_calendar)

    calendar = record.google_calendar
    return false unless calendar.respond_to?(:oauth_credential)

    calendar.oauth_credential&.user_id == user.id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user&.admin_access?
        scope.all
      else
        scope.joins(google_calendar: :oauth_credential)
             .where(oauth_credentials: { user_id: user&.id })
      end
    end
  end
end
