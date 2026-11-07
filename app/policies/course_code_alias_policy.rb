# frozen_string_literal: true

# The admin review of course code aliases (#865).
class CourseCodeAliasPolicy < ApplicationPolicy
  def index?   = admin?
  def review?  = admin?
  def destroy? = admin?
end
