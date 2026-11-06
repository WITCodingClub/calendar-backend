# frozen_string_literal: true

# A student adds and removes only their own planned programs (#868). Rows
# from LeopardWeb change only through PUT /api/user/academic_profile, which
# authorizes the user.
class StudentProgramPolicy < ApplicationPolicy
  def show?    = owner_of_record? || admin?
  def create?  = owner_of_record? && record.planned?
  def destroy? = owner_of_record? && record.planned?

  class Scope < ApplicationPolicy::Scope
    def resolve
      user&.admin_access? ? scope.all : scope.where(user_id: user&.id)
    end
  end
end
