# frozen_string_literal: true

module Audits1984
  class SessionPolicy < ApplicationPolicy
    def index?
      admin?
    end

    def show?
      admin?
    end

    def create?
      false # System-generated only
    end

    def update?
      admin?
    end

    def destroy?
      false # Console sessions should not be destroyed
    end

    class Scope < ApplicationPolicy::Scope
      def resolve
        return scope.none unless user&.admin?
        
        scope.all
      end
    end
  end
end