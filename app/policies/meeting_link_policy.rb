# frozen_string_literal: true

# Meeting links belong to the person who made them. The guest never reaches
# this policy: the public page finds a link by its token alone.
class MeetingLinkPolicy < ApplicationPolicy
  def index?   = user.present?
  def create?  = user.present?
  def destroy? = owner_of_record?

  class Scope < ApplicationPolicy::Scope
    def resolve = user ? scope.where(user: user) : scope.none
  end
end
