# frozen_string_literal: true

module Ahoy
  class VisitPolicy < ApplicationPolicy
    # Only admins+ can list visits for analytics
    def index?
      admin?
    end

    # Only admins+ can view visit details
    def show?
      admin?
    end

    # Visits are system-generated only
    def create?
      false
    end

    # Visits are immutable
    def update?
      false
    end

    # Only super_admins+ can delete visits (destructive, for cleanup)
    def destroy?
      super_admin?
    end

    class Scope < ApplicationPolicy::Scope
      def resolve
        if user&.admin_access?
          scope.all
        else
          scope.none
        end
      end

    end

  end
end
