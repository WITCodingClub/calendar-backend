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
#
# plan, plan_source, plans, start_term, and start_term_source come from
# AcademicProfiles::ProgramTimeline (#867). The My programs dashboard page
# shows the same hash.
# == Schema Information
#
# Table name: student_programs
#
#  id                :bigint           not null, primary key
#  catalog_term_uid  :integer
#  code              :string
#  college           :string
#  concentration     :string
#  degree            :string
#  department        :string
#  ended_at          :datetime
#  name              :string           not null
#  plan_name         :string
#  role              :string           not null
#  source            :string           not null
#  status            :string           default("active"), not null
#  study_path        :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  catalog_year_id   :bigint
#  degree_program_id :bigint
#  user_id           :bigint           not null
#
# Indexes
#
#  index_student_programs_on_catalog_year_id     (catalog_year_id)
#  index_student_programs_on_degree_program_id   (degree_program_id)
#  index_student_programs_on_user_id_and_status  (user_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_year_id => catalog_years.id) ON DELETE => nullify
#  fk_rails_...  (degree_program_id => degree_programs.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
class StudentProgramSerializer
  def initialize(program, timeline: nil)
    @program = program
    @timeline = timeline || AcademicProfiles::ProgramTimeline.for_program(program)
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
      ended_at:          @program.ended_at&.iso8601,
      plan:              @timeline.plan&.name,
      plan_source:       @timeline.plan_source,
      plans:             @timeline.plan_names,
      start_term:        AcademicProfiles::TermCode.label(@timeline.start_term_uid),
      start_term_source: @timeline.start_term_source
    }
  end
end
