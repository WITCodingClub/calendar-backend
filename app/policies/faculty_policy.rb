# frozen_string_literal: true

class FacultyPolicy < ApplicationPolicy
  def index?          = true
  def show?           = true
  def create?         = admin?
  def update?         = admin?
  def destroy?        = super_admin?
  def search_rmp?     = super_admin?
  def assign_rmp_id?  = super_admin?
  def auto_fill_rmp_id?   = super_admin?
  def batch_auto_fill?    = super_admin?
  def missing_rmp_ids?    = admin?
  def sync_directory?     = super_admin?
  def directory_status?   = admin?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.all
  end
end
