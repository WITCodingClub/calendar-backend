# frozen_string_literal: true

class UniversityCalendarEventPolicy < ApplicationPolicy
  def index?   = true
  def show?    = true
  def sync?     = admin?
  def backfill? = admin?
  def create?  = admin?
  def update?  = admin?
  def destroy? = super_admin?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.all
  end
end
