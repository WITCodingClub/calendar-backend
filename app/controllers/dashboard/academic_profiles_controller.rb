# frozen_string_literal: true

module Dashboard
  # Corrects the profile fields that LeopardWeb sent (#867): level, class
  # standing, admit type, and admit term. The change goes through
  # AcademicProfiles::Sync with source "student", the same path as the
  # extension settings.
  class AcademicProfilesController < Dashboard::ApplicationController
    include Dashboard::DegreePlanningFlag

    def edit
      authorize current_user, :update?

      @profile = current_user.academic_profile || current_user.build_academic_profile
    end

    def update
      authorize current_user, :update?

      AcademicProfiles::StudentCorrection.new(current_user).profile!(profile_params)
      redirect_to dashboard_programs_path, notice: "Profile saved. WIT Calendar keeps your change until LeopardWeb shows a different profile."
    rescue AcademicProfiles::InvalidProfileError => e
      redirect_to edit_dashboard_academic_profile_path, alert: e.message
    end

    private

    def profile_params
      params.expect(academic_profile: AcademicProfiles::StudentCorrection::PROFILE_FIELDS)
    end
  end
end
