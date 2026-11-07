# frozen_string_literal: true

# One ProgramPathway (#868), for the planned pathways in GET /api/user/programs,
# POST /api/user/planned_pathways, and the MCP tools my_programs and
# update_my_planned_programs. id is the slug, which those endpoints take.
# Each step names a program slug for degree_requirements.
# == Schema Information
#
# Table name: program_pathways
#
#  id                 :bigint           not null, primary key
#  active             :boolean          default(TRUE), not null
#  kind               :string           not null
#  max_shared_courses :integer
#  max_shared_credits :integer
#  name               :string           not null
#  slug               :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
# Indexes
#
#  index_program_pathways_on_slug  (slug) UNIQUE
#
class ProgramPathwaySerializer
  def initialize(pathway)
    @pathway = pathway
  end

  def as_json(*)
    {
      id:                 @pathway.slug,
      name:               @pathway.name,
      kind:               @pathway.kind,
      max_shared_courses: @pathway.max_shared_courses,
      max_shared_credits: @pathway.max_shared_credits,
      steps:              @pathway.steps.map do |step|
        { program: step.degree_program.slug, plan_years: step.plan_years }
      end
    }
  end
end
