# frozen_string_literal: true

class GoogleCalendarEventPolicy < ApplicationPolicy
  def index?
    admin?
  end

  def show?
    owner_of_record_through_calendar? || admin?
  end

  def create?
    owner_of_record_through_calendar? || super_admin?
  end

  def update?
    owner_of_record_through_calendar? || super_admin?
  end

  def destroy?
    owner_of_record_through_calendar? || can_perform_destructive_action?
  end

  private

  def owner_of_record_through_calendar?
    return false unless user && record.respond_to?(:google_calendar)
    calendar = record.google_calendar
    return false unless calendar&.respond_to?(:oauth_credential)
    oauth_credential = calendar.oauth_credential
    return false unless oauth_credential&.respond_to?(:user_id)
    oauth_credential.user_id == user.id
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
