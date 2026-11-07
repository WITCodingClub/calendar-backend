# frozen_string_literal: true

module McpTools
  # POST and DELETE /api/user/planned_programs and /api/user/planned_pathways
  # (#868): adds or removes a program or a pathway (Double Leopard, 5-year) the
  # student plans to take. It changes only planned programs, never a program
  # from LeopardWeb (AcademicProfiles::PlannedPrograms).
  class UpdateMyPlannedPrograms < BaseWriteTool
    tool_name "update_my_planned_programs"
    title "Change my planned programs"
    description "Adds a program from the degree catalog to my planned programs, such as a minor or a master's " \
                "degree I think about taking, or removes one. A planned program is only a plan in WIT Calendar: " \
                "it does not declare the program at Wentworth, and it never changes the programs that LeopardWeb " \
                "shows. To declare a program, the student asks their academic advisor. Call list_programs " \
                "to find the slug, and my_programs to see the planned programs. With pathway in place of " \
                "program, it adds or removes a pathway: a Double Leopard master's (a 3+1 or 4+1 after my own " \
                "bachelor's, with up to two graduate courses in the senior year), or a combined program such " \
                "as the 5-year B.S. plus M.Arch. Adding plans each program of the pathway that I do not have " \
                "yet, and removing removes only those planned programs. A Double Leopard pathway needs a " \
                "bachelor's program in my programs. An unknown pathway gives the list of pathway slugs."
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
        pathway:      {
          type:        "string",
          description: "In place of program: a pathway slug, for example double-leopard-computer-science-ms. To remove, " \
                       "the pathway id from my_programs planned_pathways."
        },
        catalog_year: ListPrograms::CATALOG_YEAR_SCHEMA.merge(
          description: "With add: the catalog year of the program. A student follows the catalog of the term they " \
                       "start the program in. Leave it out for the newest catalog."
        )
      },
      required: %w[action]
    )
    # program is null when nothing changed or a pathway changed. pathway is
    # null unless a pathway changed. not_changed is there only when the
    # student did not confirm.
    output_schema(
      Schemas.object(
        {
          result:           { type: "string", enum: %w[added removed unchanged] },
          program:          Schemas.nullable(Schemas::STUDENT_PROGRAM),
          pathway:          Schemas.nullable(Schemas::PROGRAM_PATHWAY),
          planned_programs: Schemas.array(Schemas::STUDENT_PROGRAM),
          planned_pathways: Schemas.array(Schemas::PROGRAM_PATHWAY),
          not_changed:      Schemas::NOT_CHANGED
        },
        optional: %i[not_changed]
      )
    )

    def perform(action:, program: nil, pathway: nil, catalog_year: nil)
      raise ToolError, "Give program or pathway, not both." if program && pathway
      raise ToolError, "Give program or pathway." if program.nil? && pathway.nil?

      planned = AcademicProfiles::PlannedPrograms.new(user)

      case action
      when "add" then pathway ? add_pathway(planned, pathway, catalog_year) : add(planned, program, catalog_year)
      when "remove"
        raise ToolError, "catalog_year is only for add." if catalog_year

        pathway ? remove_pathway(planned, pathway) : remove(planned, program)
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

    def add_pathway(planned, slug, catalog_year)
      pathway, rows = planned.build_pathway(pathway: slug, catalog_year: catalog_year)
      rows.each { |row| authorize row, :create? }

      message = "Add #{pathway.name} to your planned pathways in WIT Calendar. This adds " \
                "#{rows.map(&:name).to_sentence} (#{rows.first.catalog_year_name} catalog) to your planned programs. " \
                "This is a plan only. It does not declare a program at Wentworth."
      with_confirmation(message, unchanged: -> { current(nil) }) do
        planned.save_pathway!(pathway, rows)
        current(nil, "added", pathway)
      end
    rescue AcademicProfiles::InvalidProfileError => e
      raise ToolError, e.message
    end

    def remove_pathway(planned, slug)
      pathway, rows = planned.find_pathway(slug)
      raise ToolError, "No planned pathway #{slug}. Call my_programs to see the planned pathways." if rows.nil?

      rows.each { |row| authorize row, :destroy? }

      message = "Remove #{pathway.name} from your planned pathways in WIT Calendar. This removes " \
                "#{rows.map(&:name).to_sentence} from your planned programs."
      version = rows.map { |row| record_version(row) }.max
      with_confirmation(message, unchanged: -> { current(nil) }, version: version) do
        StudentProgram.transaction { rows.each(&:destroy!) }
        current(nil, "removed", pathway)
      end
    end

    def current(row, result = "unchanged", pathway = nil)
      programs = StudentProgramsSerializer.new(user).as_json
      {
        result:           result,
        program:          row && StudentProgramSerializer.new(row).as_json,
        pathway:          pathway && ProgramPathwaySerializer.new(pathway).as_json,
        planned_programs: programs[:planned_programs],
        planned_pathways: programs[:planned_pathways]
      }
    end
  end
end
