# frozen_string_literal: true

# A student's programs, for GET /api/user/programs and the MCP tool
# my_programs (#868): the active programs from LeopardWeb, the planned
# programs the student added, and the ended programs (changes of major,
# completed degrees), newest end first. The profile fields come from
# AcademicProfile.
class StudentProgramsSerializer
  def initialize(user)
    @user = user
  end

  def as_json(*)
    profile = @user.academic_profile
    programs = @user.student_programs.includes(:catalog_year, :degree_program).order(:id).group_by(&:status)
    ended = Array(programs["ended"]).sort_by { |program| [ program.ended_at.to_i, program.id ] }.reverse

    {
      level:                profile&.level,
      class_standing:       profile&.class_standing,
      admit_term:           AcademicProfiles::TermCode.label(profile&.admit_term_uid),
      leopardweb_synced_at: profile&.leopardweb_synced_at&.iso8601,
      programs:             json(programs["active"]),
      planned_programs:     json(programs["planned"]),
      ended_programs:       json(ended)
    }
  end

  private

  def json(programs) = Array(programs).map { |program| StudentProgramSerializer.new(program).as_json }
end
