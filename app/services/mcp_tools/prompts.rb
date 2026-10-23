# frozen_string_literal: true

module McpTools
  # The prompts of the MCP server (docs/mcp.md). A prompt is a task that the
  # student starts from the client, for example a slash command. It gives one
  # message that tells the model which tools to call, and in which order.
  # McpTools::Server lists them, and McpTools::Completions completes their
  # arguments.
  module Prompts
    def self.all
      [
        PlanTermSchedule,
        CheckMySchedule,
        PlanDegreeProgression,
        FindClassForFreeTime
      ]
    end

    def self.names = all.map(&:name_value)

    def self.find(name) = all.find { |prompt| prompt.name_value == name }
  end
end
