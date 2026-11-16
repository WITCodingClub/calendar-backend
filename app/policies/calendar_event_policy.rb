# frozen_string_literal: true

class CalendarEventPolicy < OwnedRecordPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user&.admin_access?

      scope.joins(course_calendar: :oauth_credential).where(oauth_credentials: { user_id: user&.id })
    end
  end

  private

  def owned?
    return false unless user && record.respond_to?(:course_calendar)

    record.course_calendar&.oauth_credential&.user_id == user.id
  end
end
