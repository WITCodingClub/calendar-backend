# frozen_string_literal: true

module Brightspace
  class CourseOfferingPolicy < ApplicationPolicy
    def index? = user.present?
    def show?  = user.present? && record.connection.user_id == user.id

    class Scope < ApplicationPolicy::Scope
      def resolve
        scope.for_user(user)
      end
    end
  end
end
