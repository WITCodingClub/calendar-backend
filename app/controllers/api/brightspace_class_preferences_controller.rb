# frozen_string_literal: true

module Api
  # The user's calendar and grade settings for one class.
  class BrightspaceClassPreferencesController < ApiController
    include BrightspaceFeature
    include BrightspaceScoping
    include PreferenceParams

    CALENDAR_FIELDS = %i[sync_enabled title_template description_template location_template color_id visibility].freeze

    before_action :set_class

    # GET /api/classes/:class_id/preference
    def show
      authorize preference
      render_preference
    end

    # PUT/PATCH /api/classes/:class_id/preference
    #
    # Changes only the fields in the body. reminder_settings follows the
    # calendar preference rules: "default" inherits, [] turns reminders off.
    def update
      authorize preference
      preference.assign_attributes(class_preference_params)
      preference.save!
      render_preference
    end

    private

    def set_class
      @offering = find_brightspace_class!(params[:class_id])
    end

    def preference
      @preference ||= @offering.preference || @offering.build_preference(user: current_user)
    end

    def class_preference_params
      root       = params.require(:class_preference)
      attributes = {}

      if root.key?(:calendar)
        calendar = root.require(:calendar)
        permitted = calendar.permit(*CALENDAR_FIELDS, included_kinds: [], reminder_settings: [])
        attributes.merge!(permitted.to_h.symbolize_keys.except(:reminder_settings))
        attributes[:included_kinds] = nil if calendar.key?(:included_kinds) && calendar[:included_kinds].nil?

        reminder = ActionController::Parameters.new({}).permit
        apply_reminder_settings(reminder, calendar)
        attributes[:reminder_settings] = reminder[:reminder_settings]&.map(&:to_h) if reminder.key?(:reminder_settings)
      end

      if root.key?(:grades)
        grades = root.require(:grades)
        attributes[:grade_mode] = grades[:mode] if grades.key?(:mode)
        attributes[:grade_categories] = raw_json(grades, :categories) if grades.key?(:categories)
      end

      attributes
    end

    # The grade rules have a fixed shape, which ClassPreference validates, so
    # they pass as plain JSON.
    def raw_json(source, key)
      value = source.to_unsafe_h[key.to_s]
      value.respond_to?(:map) ? JSON.parse(value.to_json) : value
    end

    def render_preference
      render json: {
        class_preference: Brightspace::ClassPreferenceSerializer.new(preference).as_json,
        version:          @offering.reload.version
      }
    end
  end
end
