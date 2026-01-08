# frozen_string_literal: true

module Audits1984
  class SessionPolicy < ApplicationPolicy
    def index?
      super_admin?
    end

    def show?
      super_admin?
    end

    def create?
      false # System-generated only
    end

    def update?
      super_admin?
    end

    def destroy?
      false # Console sessions should not be destroyed
    end

    class Scope < ApplicationPolicy::Scope
      def resolve
        return scope.none unless user&.super_admin?

        scope.all
      end

    end

  end
end
