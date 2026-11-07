# frozen_string_literal: true

module Dashboard
  # Adds and removes a pathway a student plans on the My programs page
  # (#867), such as a 4+1 master's. It uses AcademicProfiles::PlannedPrograms,
  # as POST and DELETE /api/user/planned_pathways do. Adding plans each
  # program of the pathway that the student does not have yet. Removing
  # deletes only those planned rows.
  class PlannedPathwaysController < Dashboard::ApplicationController
    include Dashboard::DegreePlanningFlag

    def create
      planned = AcademicProfiles::PlannedPrograms.new(current_user)
      pathway, programs = planned.build_pathway(pathway: params[:pathway].presence&.to_s,
                                                catalog_year: params[:catalog_year].presence&.to_s)
      programs.each { |program| authorize program, :create? }
      planned.save_pathway!(pathway, programs)

      redirect_to dashboard_programs_path(anchor: "planned-programs"), notice: "#{pathway.name} added to your planned programs."
    rescue AcademicProfiles::InvalidProfileError => e
      # build_pathway raises before a record exists to authorize. The policy
      # allows a student to plan programs only for themselves, and
      # build_pathway makes the rows for current_user, so no other check is
      # needed.
      skip_authorization unless pundit_policy_authorized?
      # The message can echo the pathway param, and the flash lives in the
      # session cookie, so a long param must not overflow it.
      redirect_to dashboard_programs_path(anchor: "planned-programs"), alert: e.message.truncate(300)
    end

    # id is the pathway slug.
    def destroy
      pathway, programs = AcademicProfiles::PlannedPrograms.new(current_user).find_pathway(params[:id])
      if programs.nil?
        # The lookup is limited to the student's own planned rows, so there
        # is no record to authorize.
        skip_authorization
        return redirect_to(dashboard_programs_path(anchor: "planned-programs"), alert: "Planned pathway not found.")
      end

      programs.each { |program| authorize program, :destroy? }
      StudentProgram.transaction { programs.each(&:destroy!) }
      redirect_to dashboard_programs_path(anchor: "planned-programs"), notice: "#{pathway.name} removed from your planned programs."
    end
  end
end
