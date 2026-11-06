# frozen_string_literal: true

# One ProgramPathway (#868), for the planned pathways in GET /api/user/programs,
# POST /api/user/planned_pathways, and the MCP tools my_programs and
# update_my_planned_programs. id is the slug, which those endpoints take.
# Each step names a program slug for degree_requirements.
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
