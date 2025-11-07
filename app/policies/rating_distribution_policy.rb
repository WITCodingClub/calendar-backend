# frozen_string_literal: true

class RatingDistributionPolicy < ApplicationPolicy
  # Everyone can list rating distributions
  def index?
    true
  end

  # Everyone can view rating distribution details
  def show?
    true
  end

  # Admins+ can create rating distributions
  def create?
    admin?
  end

  # Admins+ can update rating distributions
  def update?
    admin?
  end

  # Only super_admins+ can delete rating distributions (destructive)
  def destroy?
    super_admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end
end
