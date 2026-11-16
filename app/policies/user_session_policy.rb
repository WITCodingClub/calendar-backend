# frozen_string_literal: true

class UserSessionPolicy < ApplicationPolicy
  def index?   = owner_of_record? || admin?
  def show?    = owner_of_record? || admin?
  def destroy? = owner_of_record? || can_perform_destructive_action?

  class Scope < ApplicationPolicy::OwnerScope; end
end
