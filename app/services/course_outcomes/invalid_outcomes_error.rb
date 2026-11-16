# frozen_string_literal: true

module CourseOutcomes
  # An outcome payload the backend cannot store.
  class InvalidOutcomesError < AcademicProfiles::Error
    def initialize(message = nil, code: "invalid_outcome")
      super
    end
  end
end
