# frozen_string_literal: true

module Ahoy
  class MessagePolicy < ApplicationPolicy
    # Only admins+ can list messages for analytics
    def index?
      admin?
    end

    # Only admins+ can view message details
    def show?
      admin?
    end

    # Messages are system-generated only
    def create?
      false
    end

    # Messages are immutable
    def update?
      false
    end

    # Only super_admins+ can delete messages (destructive, for cleanup)
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
