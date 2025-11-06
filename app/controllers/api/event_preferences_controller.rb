# frozen_string_literal: true

module Api
  class EventPreferencesController < ApplicationController
    include JsonWebTokenAuthenticatable
    include FeatureFlagGated

    skip_before_action :verify_authenticity_token
    before_action :set_preferenceable

    # GET /api/meeting_times/:meeting_time_id/preference
    # GET /api/google_calendar_events/:google_calendar_event_id/preference
    def show
      preference = EventPreference.find_by(
        user: current_user,
        preferenceable: @preferenceable
      )

      # Get resolved preferences with sources
      resolver = PreferenceResolver.new(current_user)
      resolved_data = resolver.resolve_with_sources(@preferenceable)

      # Generate preview if template available
      preview = nil
      if resolved_data[:preferences][:title_template].present?
        renderer = CalendarTemplateRenderer.new
        context = CalendarTemplateRenderer.build_context_from_meeting_time(@preferenceable)
        preview = renderer.render(resolved_data[:preferences][:title_template], context)
      end

      render json: {
        individual_preference: preference ? event_preference_json(preference) : nil,
        resolved: resolved_data[:preferences],
        sources: resolved_data[:sources],
        preview: preview
      }
    end

    # PUT /api/meeting_times/:meeting_time_id/preference
    # PUT /api/google_calendar_events/:google_calendar_event_id/preference
    def update
      preference = EventPreference.find_or_initialize_by(
        user: current_user,
        preferenceable: @preferenceable
      )

      if preference.update(event_preference_params)
        render json: event_preference_json(preference)
      else
        render json: { errors: preference.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # DELETE /api/meeting_times/:meeting_time_id/preference
    # DELETE /api/google_calendar_events/:google_calendar_event_id/preference
    def destroy
      preference = EventPreference.find_by(
        user: current_user,
        preferenceable: @preferenceable
      )

      if preference
        preference.destroy
        head :no_content
      else
        head :not_found
      end
    end

    private

    def set_preferenceable
      if params[:meeting_time_id]
        @preferenceable = MeetingTime.find(params[:meeting_time_id])
      elsif params[:google_calendar_event_id]
        @preferenceable = GoogleCalendarEvent.find(params[:google_calendar_event_id])
      else
        render json: { error: "Preferenceable not specified" }, status: :bad_request
      end
    end

    def event_preference_params
      params.require(:event_preference).permit(
        :title_template,
        :description_template,
        :color_id,
        :visibility,
        reminder_settings: []
      )
    end

    def event_preference_json(preference)
      {
        title_template: preference.title_template,
        description_template: preference.description_template,
        reminder_settings: preference.reminder_settings,
        color_id: preference.color_id,
        visibility: preference.visibility
      }
    end
  end
end
