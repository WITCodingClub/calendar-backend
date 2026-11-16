# frozen_string_literal: true

module AcademicProfiles
  # A profile, transfer credit, or planned program the backend cannot store.
  class InvalidProfileError < Error
    def initialize(message = nil, code: "invalid_profile")
      super
    end
  end
end
