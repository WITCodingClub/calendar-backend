# frozen_string_literal: true

module Api
  # Saves the syllabus rules that the user confirmed. Confirming never
  # changes grade settings or calendar events by itself.
  class BrightspaceSyllabusPreferencesController < ApiController
    include BrightspaceFeature
    include BrightspaceScoping

    # PUT/PATCH /api/classes/:class_id/syllabus/preference
    #
    # source_revision must be the revision of the stored syllabus. Else the
    # source changed after the user reviewed it, and the answer is 409.
    def update
      offering = find_brightspace_class!(params[:class_id])
      root     = params.require(:syllabus_preference)
      revision = root.require(:source_revision).to_s
      current  = offering.syllabus

      if current.nil? || current.removed? || current.revision != revision
        render json: { error: "The syllabus changed. Review the new revision before you confirm it.",
                       code: "SYLLABUS_REVISION_MISMATCH" }, status: :conflict
        return
      end

      preference = offering.syllabus_preference || offering.build_syllabus_preference(user: current_user)
      authorize preference

      preference.source_revision = revision
      preference.confirmed = JSON.parse(root.to_unsafe_h["confirmed"].to_json) if root.key?(:confirmed)
      preference.save!

      render json: {
        syllabus_preference: Brightspace::SyllabusPreferenceSerializer.new(preference).as_json,
        version:             offering.reload.version
      }
    end
  end
end
