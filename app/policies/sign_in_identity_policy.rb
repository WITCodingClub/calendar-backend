# frozen_string_literal: true

class SignInIdentityPolicy < ApplicationPolicy
  def destroy? = owner_of_record? || can_perform_destructive_action?

  class Scope < ApplicationPolicy::OwnerScope; end
end
