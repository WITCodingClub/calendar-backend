# frozen_string_literal: true

class SignInIdentityPolicy < ApplicationPolicy
  def destroy? = owner_of_record? || can_perform_destructive_action?

  class Scope < ApplicationPolicy::Scope
    def resolve
      user&.admin_access? ? scope.all : scope.where(user_id: user&.id)
    end
  end
end
