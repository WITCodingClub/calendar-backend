# frozen_string_literal: true

module McpTools
  # POST /api/v1/catalog/schedule_options. Catalog::ScheduleOptions::Finder
  # has the rules. The schedule_builder flag gates it, the same as the
  # endpoint.
  class FindSchedules < BaseTool
    TIME = { type: "string", description: "A 24-hour time, HH:MM, for example 13:00." }.freeze
    DAYS = {
      type:        "array",
      items:       { type: "string", enum: Catalog::ScheduleRules::DAYS },
      description: "Days, for example [\"friday\"]. Leave it out for every day."
    }.freeze
    RANGE = {
      type:       "object",
      properties: {
        days:   DAYS,
        after:  TIME.merge(description: "The range starts at this time. Leave it out to start at midnight."),
        before: TIME.merge(description: "The range ends at this time. Leave it out to run to the end of the day.")
      }
    }.freeze
    RANGES_MAX = Catalog::ScheduleOptions::Preferences::MAX_RANGES

    tool_name "find_schedules"
    title "Find schedules"
    description "Builds and ranks schedules for a list of courses in one term. Each schedule has one section of each " \
                "course, with its lab when Banner pairs the lecture with one. A schedule never has a time conflict, a " \
                "missing lecture or lab pair, a cancelled section, or the same course two times. Each course entry is " \
                "one code or a choice of several (\"one of\"), and crns keeps sections the student already picked. Hard " \
                "preferences (blocked, earliest, latest, day_off, open_only) remove schedules. Soft preferences (avoid, " \
                "days, breaks) rank them. count is the number of schedules, at most 500 (capped). When count is 0, " \
                "relax lists the preferences to drop, each with the count it would give. not_offered lists the codes " \
                "with no section in the term. Use it in place of trying sections by hand, then show the student the " \
                "best options with their CRNs. It does not check holds, restrictions, or registration times."
    requires_scope "catalog"
    requires_flag FeatureFlags::SCHEDULE_BUILDER
    academic_planning :sections
    input_schema(
      properties: {
        term_uid:    TERM_SCHEMA,
        courses:     {
          type:        "array",
          minItems:    1,
          maxItems:    Catalog::ScheduleOptions::Input::MAX_COURSES,
          description: "The courses to take, one entry for each course.",
          items:       {
            type:       "object",
            properties: {
              codes: {
                type:        "array",
                items:       { type: "string" },
                minItems:    1,
                maxItems:    Catalog::ScheduleOptions::Input::MAX_CODES_PER_COURSE,
                description: "One course code, such as \"COMP 3350\", or several for \"one of\"."
              },
              crns:  {
                type:        "array",
                items:       { type: "integer" },
                description: "CRNs the student already picked for this course. Each schedule keeps them, also when full."
              }
            },
            required:   [ "codes" ]
          }
        },
        preferences: {
          type:       "object",
          properties: {
            blocked:   { type: "array", items: RANGE, maxItems: RANGES_MAX, description: "Times with no classes (hard)." },
            avoid:     { type: "array", items: RANGE, maxItems: RANGES_MAX, description: "Times to stay out of when possible (soft)." },
            earliest:  TIME.merge(description: "No class starts before this time (hard)."),
            latest:    TIME.merge(description: "No class ends after this time (hard)."),
            day_off:   {
              description: "\"none\", \"any\" (at least one weekday with no class), or a list of days with no class (hard).",
              anyOf:       [ { type: "string", enum: Catalog::ScheduleOptions::Preferences::DAY_OFF }, DAYS.except(:description) ]
            },
            open_only: { type: "boolean", description: "Only sections with a free seat (hard). Pinned CRNs stay." },
            days:      { type: "string", enum: Catalog::ScheduleOptions::Preferences::DAYS, description: "fewer: fewer days on campus. spread: lighter days." },
            breaks:    { type: "string", enum: Catalog::ScheduleOptions::Preferences::BREAKS, description: "tight: short gaps. lunch: a free half hour from 11:00 to 14:00." }
          }
        },
        limit:       {
          type:        "integer",
          minimum:     1,
          maximum:     Catalog::ScheduleOptions::Input::MAX_LIMIT,
          description: "How many schedules to return. Default #{Catalog::ScheduleOptions::Input::DEFAULT_LIMIT}."
        }
      },
      required: [ "courses" ]
    )
    # Catalog::ScheduleOptions::Finder#call.
    output_schema(
      Schemas.object(
        term:        Schemas::TERM_REF,
        count:       Schemas::INTEGER,
        capped:      Schemas::BOOLEAN,
        schedules:   Schemas.array(
          Schemas.object(
            rank:       Schemas::INTEGER,
            score:      Schemas::NUMBER,
            crns:       Schemas::STRINGS,
            courses:    Schemas.array(Schemas.object(code: Schemas::STRING, crns: Schemas::STRINGS)),
            highlights: Schemas::STRINGS,
            avoid_hits: Schemas::INTEGER,
            totals:     Schemas::SCHEDULE_TOTALS
          )
        ),
        relax:       Schemas.array(
          Schemas.object(
            preference: { type: "string", enum: Catalog::ScheduleOptions::Preferences::RELAXABLE.map(&:to_s) },
            label:      Schemas::STRING,
            count:      Schemas::INTEGER
          )
        ),
        not_offered: Schemas::STRINGS
      )
    )

    def perform(courses:, term_uid: nil, preferences: nil, limit: nil)
      params = { term_uid: find_term(term_uid).uid, courses: courses, preferences: preferences, limit: limit }.compact
      Catalog::ScheduleOptions::Finder.new(params, surface: "mcp").call
    rescue Catalog::FilterError => e
      raise ToolError, e.message
    rescue Catalog::ScheduleOptions::BusyError
      raise ToolError, "The schedule builder is busy. Wait a moment, then call find_schedules again."
    end
  end
end
