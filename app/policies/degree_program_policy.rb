# frozen_string_literal: true

# The admin pages that show a program, its requirement set for each catalog
# year, its plans of study, and its elective lists (#864).
class DegreeProgramPolicy < ApplicationPolicy
  def index? = admin?
  def show?  = admin?
end
