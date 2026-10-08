# frozen_string_literal: true

# A row that the user owns for a class is part of the data of that class, so
# saving or deleting it raises the class version.
module Brightspace
  module VersionBumping
    extend ActiveSupport::Concern

    included do
      after_commit :bump_course_offering_version
    end

    private

    def bump_course_offering_version
      course_offering&.bump_version!
    end
  end
end
