# frozen_string_literal: true

# Records that anyone can read. Admins change them, and only super admins
# delete them.
class PublicRecordPolicy < ApplicationPolicy
  def index?   = true
  def show?    = true
  def create?  = admin?
  def update?  = admin?
  def destroy? = super_admin?

  class Scope < ApplicationPolicy::AllScope; end
end
