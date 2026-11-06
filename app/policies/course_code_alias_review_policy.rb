# frozen_string_literal: true

# The review queue of course code aliases (#865). An admin marks an alias as
# checked. A super admin can delete a wrong one.
class CourseCodeAliasReviewPolicy < ApplicationPolicy
  def index?   = admin?
  def update?  = admin?
  def destroy? = super_admin?
end
