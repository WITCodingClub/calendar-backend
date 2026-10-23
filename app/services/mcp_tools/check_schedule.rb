# frozen_string_literal: true

module McpTools
  # GET /api/v1/catalog/schedule_check. GraphQL: scheduleCheck.
  class CheckSchedule < BaseTool
    tool_name "check_schedule"
    title "Check a schedule"
    description "Checks a set of sections that would be taken together in one term: time conflicts, " \
                "lectures and labs that must be registered as a linked pair, the same course twice, " \
                "and totals (credits, days, earliest start, latest end, meetings before 9:00). " \
                "Lecture and lab pairs come from Banner, so trust this over link identifiers. " \
                "Use it before you suggest a schedule."
    requires_scope "catalog"
    academic_planning :sections
    # Hosts with the MCP Apps extension show the result as a week grid.
    meta WeekGridApp.tool_meta
    input_schema(
      properties: {
        term_uid: TERM_SCHEMA,
        crns:     {
          type:        "array",
          items:       { type: "integer" },
          minItems:    1,
          maxItems:    Catalog::ScheduleCheck::MAX_CRNS,
          description: "Every CRN in the schedule, including labs."
        }
      },
      required: [ "crns" ]
    )

    def perform(crns:, term_uid: nil)
      Catalog::ScheduleCheck.new(term_uid: find_term(term_uid).uid, crns: crns).call
    rescue Catalog::FilterError => e
      raise ToolError, e.message
    end
  end
end
