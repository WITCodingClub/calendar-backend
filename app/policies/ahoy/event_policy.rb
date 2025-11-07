# frozen_string_literal: true

module Ahoy
  class EventPolicy < ApplicationPolicy
    # Only admins+ can list events for analytics
    def index?
      admin?
    end

    # Only admins+ can view event details
    def show?
      admin?
    end

    # Events are system-generated only
    def create?
      false
    end

    # Events are immutable
    def update?
      false
    end

    # Only super_admins+ can delete events (destructive, for cleanup)
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
