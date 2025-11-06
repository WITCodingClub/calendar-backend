# frozen_string_literal: true

module Api
  class CalendarPreferencesController < ApiController
    before_action :set_calendar_preference, only: [:show, :update, :destroy]

    # GET /api/calendar_preferences
    def index
      global_pref = current_user.calendar_preferences.find_by(scope: :global)
      event_type_prefs = current_user.calendar_preferences.where(scope: :event_type)

      render json: {
        global: global_pref ? preference_json(global_pref) : nil,
        event_types: event_type_prefs.index_by(&:event_type).transform_values { |p| preference_json(p) }
      }
    end

    # GET /api/calendar_preferences/global
    # GET /api/calendar_preferences/:event_type
    def show
      render json: preference_json(@calendar_preference)
    end

    # PUT /api/calendar_preferences/global
    # PUT /api/calendar_preferences/:event_type
    def update
      if @calendar_preference.update(calendar_preference_params)
        render json: preference_json(@calendar_preference)
      else
        render json: { errors: @calendar_preference.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # DELETE /api/calendar_preferences/:event_type
    def destroy
      @calendar_preference.destroy
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

      meeting_time = MeetingTime.find_by(id: meeting_time_id)
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
        }, status: :unprocessable_entity
      end
    end

    private

    def set_calendar_preference
      scope_param = params[:id] || params[:scope]

      if scope_param == "global"
        @calendar_preference = current_user.calendar_preferences.find_or_initialize_by(
          scope: :global
        )
      else
        # Event type preference
        @calendar_preference = current_user.calendar_preferences.find_or_initialize_by(
          scope: :event_type,
          event_type: scope_param
        )
      end
    end

    def calendar_preference_params
      params.expect(
        calendar_preference: [:title_template,
                              :description_template,
                              :color_id,
                              :visibility,
                              { reminder_settings: [] }]
      )
    end

    def preference_json(preference)
      {
        scope: preference.scope,
        event_type: preference.event_type,
        title_template: preference.title_template,
        description_template: preference.description_template,
        reminder_settings: preference.reminder_settings,
        color_id: preference.color_id,
        visibility: preference.visibility
      }
    end

  end
end
