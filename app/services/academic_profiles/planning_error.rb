# frozen_string_literal: true

module AcademicProfiles
  # A degree planning request that cannot be answered: a bad argument, or no
  # program to check. The API answers 422 with the message, and an MCP tool
  # gives it as a tool error. code is the error code of the API body, or nil.
  class PlanningError < StandardError
    def code = nil
  end
end
