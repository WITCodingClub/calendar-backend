# frozen_string_literal: true

# The review queue of course code aliases (#865). An admin marks an alias as
# checked, or deletes a wrong one.
class CourseCodeAliasReviewPolicy < ApplicationPolicy
  def index?   = admin?
  def update?  = admin?
  def destroy? = admin?
end
