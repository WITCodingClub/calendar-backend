# frozen_string_literal: true

module Dashboard
  # Adds and removes the programs a student plans on the My programs page
  # (#867), such as a minor they think about taking. It uses
  # AcademicProfiles::PlannedPrograms, as POST and DELETE
  # /api/user/planned_programs do. A LeopardWeb program never changes here.
  class PlannedProgramsController < Dashboard::ApplicationController
    include Dashboard::DegreePlanningFlag

    def create
      planned = AcademicProfiles::PlannedPrograms.new(current_user)
      program = planned.build(program: params[:program].presence&.to_s, catalog_year: params[:catalog_year].presence&.to_s)
      authorize program, :create?
      planned.save!(program)

      redirect_to dashboard_programs_path(anchor: "planned-programs"), notice: "#{program.name} added to your planned programs."
    rescue AcademicProfiles::InvalidProfileError => e
      # build raises before a record exists to authorize. The policy allows a
      # student to plan programs only for themselves, and build makes the row
      # for current_user, so no other check is needed.
      skip_authorization unless pundit_policy_authorized?
      redirect_to dashboard_programs_path(anchor: "planned-programs"), alert: e.message
    end

    def destroy
      program = AcademicProfiles::PlannedPrograms.new(current_user).find(params[:id])
      unless program
        # The lookup is limited to the student's own planned rows, so there
        # is no record to authorize.
        skip_authorization
        return redirect_to(dashboard_programs_path(anchor: "planned-programs"), alert: "Planned program not found.")
      end

      authorize program, :destroy?
      program.destroy!
      redirect_to dashboard_programs_path(anchor: "planned-programs"), notice: "#{program.name} removed from your planned programs."
    end
  end
end
