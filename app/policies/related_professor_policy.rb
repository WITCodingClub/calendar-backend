# frozen_string_literal: true

class RelatedProfessorPolicy < ApplicationPolicy
  # Everyone can list related professors
  def index?
    true
  end

  # Everyone can view related professor details
  def show?
    true
  end

  # Admins+ can create related professor records
  def create?
    admin?
  end

  # Admins+ can update related professor records
  def update?
    admin?
  end

  # Only super_admins+ can delete related professor records (destructive)
  def destroy?
    super_admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end

  end

end
