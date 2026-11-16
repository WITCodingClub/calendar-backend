# frozen_string_literal: true

class PasskeyPolicy < ApplicationPolicy
  def index?   = owner_of_record? || admin?
  def show?    = owner_of_record? || admin?
  def create?  = owner_of_record?
  def destroy? = owner_of_record? || can_perform_destructive_action?

  class Scope < ApplicationPolicy::OwnerScope; end
end
