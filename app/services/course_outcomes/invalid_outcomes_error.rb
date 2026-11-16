# frozen_string_literal: true

module CourseOutcomes
  # An outcome payload the backend cannot store. The controller renders it as
  # a 422 with the code.
  class InvalidOutcomesError < StandardError
    attr_reader :code

    def initialize(message, code: "invalid_outcome")
      @code = code
      super(message)
    end
  end
end
