# frozen_string_literal: true

module AcademicProfiles
  # A degree planning request that cannot be answered: a bad argument, or no
  # program to check.
  class PlanningError < Error; end
end
