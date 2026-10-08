# frozen_string_literal: true

module Brightspace
  class AssignmentPolicy < ApplicationPolicy
    def index? = user.present?
    def show?  = user.present? && record.course_offering.connection.user_id == user.id

    class Scope < ApplicationPolicy::Scope
      def resolve
        scope.joins(:course_offering).merge(Brightspace::CourseOffering.for_user(user))
      end
    end
  end
end
