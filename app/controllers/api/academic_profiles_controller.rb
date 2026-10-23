# frozen_string_literal: true

module Api
  # The academic profile the extension reads from LeopardWeb: level, class
  # standing, admit term, and programs with their catalog terms (#529).
  class AcademicProfilesController < BaseController
    PAYLOAD_KEYS = %w[source level class_standing admit_type admit_term programs].freeze

    authenticate_with_token

    # GET /api/user/academic_profile
    def show
      authorize current_user, :show?

      render json: AcademicProfileSerializer.new(current_user).as_json
    end

    # PUT /api/user/academic_profile
    def update
      authorize current_user, :update?

      AcademicProfiles::Sync.new(current_user, params.to_unsafe_h.slice(*PAYLOAD_KEYS)).call

      render json: AcademicProfileSerializer.new(current_user.reload).as_json
    rescue AcademicProfiles::InvalidProfileError => e
      render_error e.message, status: :unprocessable_content, code: e.code
    end
  end
end
