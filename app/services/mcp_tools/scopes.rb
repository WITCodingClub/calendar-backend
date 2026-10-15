# frozen_string_literal: true

module McpTools
  # The OAuth scopes of the MCP server (docs/mcp.md). Each tool names one
  # scope with requires_scope, and the consent page shows one checkbox for
  # each scope that the client asks for.
  #
  # The Doorkeeper config, the discovery documents, client registration, the
  # consent page, and Settings all read the list from here.
  module Scopes
    Scope = Data.define(:name, :group, :label, :description, :default)

    ALL = [
      Scope.new(name: "catalog", group: :read, label: "Course catalog",
                description: "Courses, sections, instructors, reviews, terms, and the university calendar",
                default: true),
      Scope.new(name: "schedule:read", group: :read, label: "Your schedule",
                description: "Your courses, meeting times, final exams, and busy times",
                default: true),
      Scope.new(name: "friends:read", group: :read, label: "Your friends",
                description: "Your friends list, friend requests, and the busy times your friends share with you",
                default: true),
      Scope.new(name: "settings:read", group: :read, label: "Your calendar settings",
                description: "Event titles, colors, reminders, and visibility",
                default: true),
      Scope.new(name: "settings:write", group: :change, label: "Change calendar settings",
                description: "Event titles, colors, reminders, and visibility",
                default: false),
      Scope.new(name: "notifications:write", group: :change, label: "Turn notifications off and on",
                description: "Pause or resume your class reminders",
                default: false),
      Scope.new(name: "friends:requests", group: :change, label: "Friend requests",
                description: "Send, accept, decline, and cancel friend requests",
                default: false),
      Scope.new(name: "friends:meetings", group: :change, label: "Meetings with friends",
                description: "Create, change, cancel, and leave meetings with friends",
                default: false),
      Scope.new(name: "friends:groups", group: :change, label: "Friend groups",
                description: "Create, rename, and delete friend groups, and add or remove members",
                default: false)
    ].freeze

    BY_NAME = ALL.index_by(&:name).freeze
    NAMES   = ALL.map(&:name).freeze

    # The scope of tokens issued before the scopes were split. It still gives
    # every read scope, so those connections keep the tools they had.
    LEGACY_READ = "read"
    LEGACY_READ_SCOPES = ALL.select { |scope| scope.group == :read }.map(&:name).freeze

    # Public data. Every token gets it, so the consent page has no checkbox.
    ALWAYS = "catalog"

    # MCP clients that ask the student for more scopes when a tool call
    # answers 403 insufficient_scope (step-up authorization). Every other
    # client gets a tool error instead, because a 403 fails the whole
    # request there. Add a client only after a test shows that it signs in
    # again and retries. Each entry matches the client's uid (its client ID
    # metadata document URL) or, for a client that registered itself, its name.
    STEP_UP_CLIENTS = [].freeze

    module_function

    # The scope names a token's scope string gives, with the legacy read
    # scope expanded.
    def expand(scopes)
      names = scopes.to_s.split
      names = (names - [ LEGACY_READ ]) | LEGACY_READ_SCOPES if names.include?(LEGACY_READ)
      names & NAMES
    end

    def label(name) = BY_NAME.fetch(name).label

    def step_up?(application)
      return false if application.nil?

      STEP_UP_CLIENTS.include?(application.uid) || STEP_UP_CLIENTS.include?(application.name)
    end
  end
end
