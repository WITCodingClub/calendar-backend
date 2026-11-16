# frozen_string_literal: true

module AcademicProfiles
  # A degree planning request the backend cannot answer, or a profile, credit,
  # outcome, or planned program it cannot store. The message is for the
  # student. The API answers 422 with the message and code (Api::BaseController),
  # and an MCP tool gives the message as a tool error (McpTools::BaseTool).
  # code is the error code of the API body, or nil for VALIDATION_FAILED.
  class Error < StandardError
    attr_reader :code

    def initialize(message = nil, code: nil)
      @code = code
      super(message)
    end
  end
end
