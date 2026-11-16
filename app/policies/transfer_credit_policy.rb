# frozen_string_literal: true

# A student sees and changes only their own transfer credit (#1020). The
# list and the transcript sync act on the signed-in student's own rows, so
# they need only a user.
class TransferCreditPolicy < ApplicationPolicy
  def index?   = user.present?
  def replace? = user.present?
  def create?  = user.present?
  def destroy? = owner_of_record?

  class Scope < ApplicationPolicy::Scope
    def resolve
      user&.admin_access? ? scope.all : scope.where(user_id: user&.id)
    end
  end
end
