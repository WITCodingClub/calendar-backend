# frozen_string_literal: true

# A student's academic profile and active programs, for
# GET and PUT /api/user/academic_profile. A student with no profile gets null
# fields and no programs.
class AcademicProfileSerializer
  def initialize(user)
    @user = user
  end

  def as_json(*)
    profile = @user.academic_profile

    {
      level:           profile&.level,
      class_standing:  profile&.class_standing,
      admit_type:      profile&.admit_type,
      admit_term:      AcademicProfiles::TermCode.label(profile&.admit_term_uid),
      admit_term_code: profile&.admit_term_uid&.to_s,
      updated_at:      profile&.updated_at&.iso8601,
      programs:        @user.student_programs.active.order(:id).map { |program| program_json(program) }
    }
  end

  private

  def program_json(program)
    {
      id:                program.public_id,
      role:              program.role,
      code:              program.code,
      name:              program.name,
      degree:            program.degree,
      college:           program.college,
      department:        program.department,
      concentration:     program.concentration,
      study_path:        program.study_path,
      catalog_term:      program.catalog_term,
      catalog_term_code: program.catalog_term_uid&.to_s,
      catalog_year:      program.catalog_year,
      # Null until programs link to the degree catalog (#526).
      matched:           nil,
      source:            program.source
    }
  end
end
