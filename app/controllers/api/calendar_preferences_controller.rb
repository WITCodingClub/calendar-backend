# frozen_string_literal: true

module Api
  class CalendarPreferencesController < ApiController
    before_action :set_calendar_preference, only: [:show, :update, :destroy]

    # GET /api/calendar_preferences
    def index
      preferences = policy_scope(current_user.calendar_preferences)
      global_pref = preferences.find_by(scope: :global)
      event_type_prefs = preferences.where(scope: :event_type)
      uni_cal_category_prefs = preferences.where(scope: :uni_cal_category)

      render json: {
        global: global_pref ? preference_json(global_pref) : nil,
        event_types: event_type_prefs.index_by(&:event_type).transform_values { |p| preference_json(p) },
        uni_cal_categories: uni_cal_category_prefs.index_by(&:event_type).transform_values { |p| preference_json(p) }
      }
    end

    # GET /api/calendar_preferences/global
    # GET /api/calendar_preferences/:event_type (e.g., lecture, laboratory)
    # GET /api/calendar_preferences/uni_cal:category (e.g., uni_cal:holiday, uni_cal:deadline)
    def show
      authorize @calendar_preference
      render json: preference_json(@calendar_preference)
    end

    # PUT /api/calendar_preferences/global
    # PUT /api/calendar_preferences/:event_type (e.g., lecture, laboratory)
    # PUT /api/calendar_preferences/uni_cal:category (e.g., uni_cal:holiday, uni_cal:deadline)
    def update
      authorize @calendar_preference
      if @calendar_preference.update(calendar_preference_params)
        # Trigger immediate calendar sync in background
        GoogleCalendarSyncJob.perform_later(current_user, force: true)

        render json: preference_json(@calendar_preference)
      else
        render json: { errors: @calendar_preference.errors.full_messages }, status: :unprocessable_content
      end
    end

    # DELETE /api/calendar_preferences/:event_type (e.g., lecture, laboratory)
    # DELETE /api/calendar_preferences/uni_cal:category (e.g., uni_cal:holiday, uni_cal:deadline)
    def destroy
      authorize @calendar_preference
      @calendar_preference.destroy

      # Trigger immediate calendar sync in background
      GoogleCalendarSyncJob.perform_later(current_user, force: true)

      head :no_content
    end

    # POST /api/calendar_preferences/preview
    def preview
      template = params[:template]
      meeting_time_id = params[:meeting_time_id]

      if template.blank?
        render json: { error: "Template is required" }, status: :bad_request
        return
      end

      if meeting_time_id.blank?
        render json: { error: "meeting_time_id is required" }, status: :bad_request
        return
      end

      # Accept both internal ID and public_id
      meeting_time = find_by_any_id(MeetingTime, meeting_time_id)
      meeting_time = MeetingTime.includes(course: :faculties).find_by(id: meeting_time&.id) if meeting_time
      unless meeting_time
        render json: { error: "Meeting time not found" }, status: :not_found
        return
      end

      # Validate and render template
      begin
        CalendarTemplateRenderer.validate_template(template)
        renderer = CalendarTemplateRenderer.new
        context = CalendarTemplateRenderer.build_context_from_meeting_time(meeting_time)
        rendered = renderer.render(template, context)

        render json: {
          rendered: rendered,
          valid: true
        }
      rescue CalendarTemplateRenderer::InvalidTemplateError => e
        render json: {
          valid: false,
          error: e.message
        }, status: :unprocessable_content
      end
    end

    private

    def set_calendar_preference
      scope_param = params[:id] || params[:scope]

      if scope_param == "global"
        @calendar_preference = current_user.calendar_preferences.find_or_initialize_by(
          scope: :global
        )
      elsif scope_param.start_with?("uni_cal:")
        # University calendar category preference (e.g., "uni_cal:holiday", "uni_cal:deadline")
        category = scope_param.delete_prefix("uni_cal:")
        @calendar_preference = current_user.calendar_preferences.find_or_initialize_by(
          scope: :uni_cal_category,
          event_type: category
        )
      else
        # Event type preference (e.g., "lecture", "laboratory")
        @calendar_preference = current_user.calendar_preferences.find_or_initialize_by(
          scope: :event_type,
          event_type: scope_param
        )
      end
    end

    def calendar_preference_params
      permitted = params.require(:calendar_preference).permit(
        :title_template,
        :description_template,
        :location_template,
        :color_id,
        :visibility,
        reminder_settings: []
      )

      # If reminder_settings is present, manually permit the nested attributes
      if params[:calendar_preference][:reminder_settings].present?
        permitted[:reminder_settings] = params[:calendar_preference][:reminder_settings].map do |reminder|
          reminder.permit(:time, :method, :type)
        end
      elsif params[:calendar_preference].key?(:reminder_settings)
        # Explicitly set to empty array if key is present but value is empty
        permitted[:reminder_settings] = []
      end

      # Convert WITCC hex color to Google color ID if needed
      if permitted[:color_id].is_a?(String) && permitted[:color_id].start_with?("#")
        permitted[:color_id] = GoogleColors.witcc_to_color_id(permitted[:color_id])
      end

      permitted
    end

    def preference_json(preference)
      {
        scope: preference.scope,
        event_type: preference.event_type,
        title_template: preference.title_template,
        description_template: preference.description_template,
        location_template: preference.location_template,
        reminder_settings: transform_reminder_settings(preference.reminder_settings),
        color_id: normalize_color_to_witcc_hex(preference.color_id),
        visibility: preference.visibility
      }
    end

  end
end
