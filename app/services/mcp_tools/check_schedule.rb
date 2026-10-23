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
    # Catalog::ScheduleCheck#call.
    output_schema(
      Schemas.object(
        term:          Schemas::TERM_REF,
        sections:      Schemas.array(
          Schemas.object(
            crn:           Schemas::INTEGER,
            course_code:   Schemas::STRING,
            title:         Schemas::STRING,
            schedule_type: Schemas::STRING,
            credit_hours:  Schemas.nullable(Schemas::INTEGER),
            meeting_times: Schemas.array(Schemas.object(day: Schemas::DAY, begin_time: Schemas::TIME, end_time: Schemas::TIME))
          )
        ),
        not_found:     Schemas::INTEGERS,
        cancelled:     Schemas::INTEGERS,
        conflicts:     Schemas.array(
          Schemas.object(crns: Schemas::INTEGERS, day: Schemas::DAY, times: Schemas::STRINGS)
        ),
        link_problems: Schemas.array(
          Schemas.object(
            crn:             Schemas::INTEGER,
            source:          Schemas::LINKED[:properties][:source],
            partner_crns:    Schemas::INTEGERS,
            partner_options: Schemas.array(Schemas::INTEGERS),
            problem:         { type: "string", enum: %w[missing_partner unverified_link] },
            message:         Schemas::STRING
          )
        ),
        duplicates:    Schemas.array(Schemas.object(course_code: Schemas::STRING, crns: Schemas::INTEGERS)),
        totals:        Schemas.object(
          credit_hours:         Schemas::INTEGER,
          days:                 Schemas.array(Schemas::DAY),
          earliest_start:       Schemas.nullable(Schemas::TIME),
          latest_end:           Schemas.nullable(Schemas::TIME),
          meetings_before_nine: Schemas::INTEGER
        )
      )
    )

    def perform(crns:, term_uid: nil)
      Catalog::ScheduleCheck.new(term_uid: find_term(term_uid).uid, crns: crns).call
    rescue Catalog::FilterError => e
      raise ToolError, e.message
    end
  end
end
