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
                "Use it before you suggest a schedule. Sections with data older than " \
                "#{Courses::Processor::CATALOG_FRESH_FOR.in_hours.to_i} hours in a current or future term get a Banner refresh in the background. " \
                "To read Banner itself, see get_section. A schedule with a time conflict needs a time conflict " \
                "override from #{Policy::OVERRIDE_OFFICE}: give the minutes of overlap."
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
    output_schema(Schemas::SCHEDULE_CHECK)

    def perform(crns:, term_uid: nil)
      result = Catalog::ScheduleCheck.new(term_uid: find_term(term_uid).uid, crns: crns).call
      refresh_stale_sections(result[:term][:uid], result[:sections].pluck(:crn))
      result
    end
  end
end
