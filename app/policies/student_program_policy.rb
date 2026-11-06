# frozen_string_literal: true

# A student adds and removes only their own planned programs (#868). Rows
# from LeopardWeb change only through AcademicProfiles::Sync: PUT
# /api/user/academic_profile and the My programs dashboard page (#867).
class StudentProgramPolicy < ApplicationPolicy
  def show?    = owner_of_record? || admin?
  def create?  = owner_of_record? && record.planned?
  def destroy? = owner_of_record? && record.planned?

  # A student corrects a value that LeopardWeb sent on an active program.
  # An ended program is history and does not change.
  def update? = owner_of_record? && record.active?

  # A student picks the plan of study of an active or a planned program.
  def update_plan? = owner_of_record? && !record.ended?

  class Scope < ApplicationPolicy::Scope
    def resolve
      user&.admin_access? ? scope.all : scope.where(user_id: user&.id)
    end
  end
end
