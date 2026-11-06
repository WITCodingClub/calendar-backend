# frozen_string_literal: true

# The review queue of requirement sets read from a PDF catalog (#865). An
# admin reads a set and marks it as checked.
class RequirementSetReviewPolicy < ApplicationPolicy
  def index?  = admin?
  def show?   = admin?
  def update? = admin?
end
