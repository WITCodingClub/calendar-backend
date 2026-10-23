# frozen_string_literal: true

module AcademicProfiles
  # A profile or outcome payload the backend cannot store. The controller
  # renders it as a 422 with the code.
  class InvalidProfileError < StandardError
    attr_reader :code

    def initialize(message, code: "invalid_profile")
      @code = code
      super(message)
    end
  end
end
