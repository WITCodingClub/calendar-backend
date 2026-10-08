# frozen_string_literal: true

# A row that the user owns for one of their classes. The owner must be the
# user of the class.
module Brightspace
  module OwnedByClassUser
    extend ActiveSupport::Concern

    included do
      belongs_to :user
      belongs_to :course_offering, class_name: "Brightspace::CourseOffering"

      validate :course_offering_belongs_to_user
    end

    private

    # A check across two associations, which no matcher covers.
    def course_offering_belongs_to_user
      return if course_offering.nil? || user.nil?

      errors.add(:course_offering, "is not one of your classes") unless course_offering.connection.user_id == user_id
    end
  end
end
