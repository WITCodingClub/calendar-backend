# frozen_string_literal: true

module Brightspace
  class ConnectionPolicy < ApplicationPolicy
    def show?    = owner_of_record?
    def create?  = owner_of_record?
    def destroy? = owner_of_record?
    def sync?    = owner_of_record? && record.active?

    class Scope < ApplicationPolicy::Scope
      def resolve
        scope.where(user_id: user&.id)
      end
    end
  end
end
