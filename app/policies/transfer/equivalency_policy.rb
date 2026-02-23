# frozen_string_literal: true

module Transfer
  class EquivalencyPolicy < ApplicationPolicy
    # Transfer equivalencies are public read - anyone can view
    def index?
      true
    end

    def show?
      true
    end

    # Only admins can trigger sync
    def sync?
      admin?
    end

    class Scope < ApplicationPolicy::Scope
      def resolve
        scope.all
      end

    end

  end
end
