# frozen_string_literal: true

# One StudentProgram, for GET /api/user/programs, POST
# /api/user/planned_programs, and the MCP tools my_programs and
# update_my_planned_programs. GET /api/user/academic_profile keeps its own
# shape (AcademicProfileSerializer), the extension contract of #529.
#
# program is the slug of the linked DegreeProgram, which degree_requirements
# and GET /api/v1/catalog/programs/:slug take. It is null when the program
# has no link to the degree catalog. pathway is the slug of the
# ProgramPathway a planned row was added with, or null.
class StudentProgramSerializer
  def initialize(program)
    @program = program
  end

  def as_json(*)
    {
      id:                @program.public_id,
      role:              @program.role,
      status:            @program.status,
      code:              @program.code,
      name:              @program.name,
      degree:            @program.degree,
      college:           @program.college,
      department:        @program.department,
      concentration:     @program.concentration,
      study_path:        @program.study_path,
      catalog_term:      @program.catalog_term,
      catalog_term_code: @program.catalog_term_uid&.to_s,
      catalog_year:      @program.catalog_year_name,
      program:           @program.degree_program&.slug,
      pathway:           @program.program_pathway&.slug,
      matched:           @program.matched?,
      source:            @program.source,
      ended_at:          @program.ended_at&.iso8601
    }
  end
end
