# frozen_string_literal: true

class CourseCalendarPolicy < OwnedRecordPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user&.admin_access?

      scope.joins(:oauth_credential).where(oauth_credentials: { user_id: user&.id })
    end
  end

  private

  def owned? = owner_of_record_through?(:oauth_credential)
end
