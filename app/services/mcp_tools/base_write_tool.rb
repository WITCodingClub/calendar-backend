# frozen_string_literal: true

module McpTools
  # Base for an MCP tool that changes data. It changes only the signed-in
  # user's own data, through the same models and policies as the matching
  # API endpoint. A write scope (McpTools::Scopes) is off by default on the
  # consent page, so the student turns each one on.
  #
  # Before a write tool changes data, it asks the student to confirm, if the
  # client can ask (with_confirmation, McpTools::Confirmation).
  class BaseWriteTool < BaseTool
    WRITE = {
      read_only_hint:   false,
      destructive_hint: false,
      idempotent_hint:  true,
      open_world_hint:  false
    }.freeze

    NOT_CHANGED_MESSAGE = "Nothing changed. The student did not confirm the change. Do not call the tool again " \
                          "unless the student asks for the change again."

    class << self
      def inherited(subclass)
        super
        subclass.annotations(WRITE)
      end

      # Marks a tool that can delete or replace the student's data
      # (destructive), or that changes a system outside WIT Calendar, such
      # as the student's Google or Outlook calendar (open_world). Clients and
      # app directories read these hints, so they must match what the tool does.
      def write_hints(destructive: false, open_world: false)
        annotations(WRITE.merge(destructive_hint: destructive, open_world_hint: open_world))
      end
    end

    private

    # Runs the block, which makes the change, when the student confirms it or
    # when the client cannot ask. Otherwise returns the question for the
    # client, or the result of unchanged with not_changed added. A nil message
    # means nothing changes, so there is nothing to confirm.
    #
    # version: a value that changes each time the record changes (its
    # updated_at), or nil for a record that does not exist yet. It binds the
    # answer to the record, so the same answer cannot make the change twice.
    def with_confirmation(message, unchanged:, version: nil)
      return yield if message.nil?

      outcome = Confirmation.new(server_context, user: user).call(message, version: version)
      case outcome
      when :accept then yield
      when MCP::Server::InputRequiredResult then outcome
      else
        unchanged.call.merge(not_changed: { reason: outcome == :decline ? "declined" : "cancelled", message: NOT_CHANGED_MESSAGE })
      end
    end

    def record_version(record) = record.persisted? ? record.updated_at&.utc&.iso8601(6) : nil
  end
end
