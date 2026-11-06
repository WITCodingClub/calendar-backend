# frozen_string_literal: true

module McpTools
  # POST and DELETE /api/user/planned_programs (#868): adds or removes a
  # program the student plans to take. It changes only planned programs,
  # never a program from LeopardWeb (AcademicProfiles::PlannedPrograms).
  class UpdateMyPlannedPrograms < BaseWriteTool
    tool_name "update_my_planned_programs"
    title "Change my planned programs"
    description "Adds a program from the degree catalog to my planned programs, such as a minor or a master's " \
                "degree I think about taking, or removes one. A planned program is only a plan in WIT Calendar: " \
                "it does not declare the program at Wentworth, and it never changes the programs that LeopardWeb " \
                "shows. To declare a program, the student asks their academic advisor. Call list_programs " \
                "to find the slug, and my_programs to see the planned programs."
    requires_scope "programs:write"
    academic_planning :degree_requirements
    input_schema(
      properties: {
        action:       { type: "string", enum: %w[add remove], description: "add or remove a planned program." },
        program:      {
          type:        "string",
          description: "The program slug from list_programs, for example computer-networking-minor. To remove, " \
                       "the slug or the id from my_programs."
        },
        catalog_year: ListPrograms::CATALOG_YEAR_SCHEMA.merge(
          description: "With add: the catalog year of the program. A student follows the catalog of the term they " \
                       "start the program in. Leave it out for the newest catalog."
        )
      },
      required: %w[action program]
    )
    # program is null when nothing changed. not_changed is there only when
    # the student did not confirm.
    output_schema(
      Schemas.object(
        {
          result:           { type: "string", enum: %w[added removed unchanged] },
          program:          Schemas.nullable(Schemas::STUDENT_PROGRAM),
          planned_programs: Schemas.array(Schemas::STUDENT_PROGRAM),
          not_changed:      Schemas::NOT_CHANGED
        },
        optional: %i[not_changed]
      )
    )

    def perform(action:, program:, catalog_year: nil)
      planned = AcademicProfiles::PlannedPrograms.new(user)

      case action
      when "add" then add(planned, program, catalog_year)
      when "remove"
        raise ToolError, "catalog_year is only for add." if catalog_year

        remove(planned, program)
      else raise ToolError, "action must be add or remove."
      end
    end

    private

    def add(planned, program, catalog_year)
      row = planned.build(program: program, catalog_year: catalog_year)
      authorize row, :create?

      message = "Add #{row.name} (#{row.catalog_year_name} catalog) to your planned programs in WIT Calendar. " \
                "This is a plan only. It does not declare the program at Wentworth."
      with_confirmation(message, unchanged: -> { current(nil) }) do
        planned.save!(row)
        current(row, "added")
      end
    rescue AcademicProfiles::InvalidProfileError => e
      raise ToolError, e.message
    end

    def remove(planned, program)
      row = planned.find(program)
      raise ToolError, "No planned program #{program}. Call my_programs to see the planned programs." if row.nil?

      authorize row, :destroy?

      message = "Remove #{row.name} (#{row.catalog_year_name} catalog) from your planned programs in WIT Calendar."
      with_confirmation(message, unchanged: -> { current(nil) }, version: record_version(row)) do
        row.destroy!
        current(row, "removed")
      end
    end

    def current(row, result = "unchanged")
      {
        result:           result,
        program:          row && StudentProgramSerializer.new(row).as_json,
        planned_programs: StudentProgramsSerializer.new(user).as_json[:planned_programs]
      }
    end
  end
end
