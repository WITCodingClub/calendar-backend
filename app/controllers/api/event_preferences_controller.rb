# frozen_string_literal: true

module Api
  class EventPreferencesController < ApiController
    before_action :set_preferenceable

    # GET /api/meeting_times/:meeting_time_id/preference
    # GET /api/google_calendar_events/:google_calendar_event_id/preference
    def show
      preference = EventPreference.find_by(
        user: current_user,
        preferenceable: @preferenceable
      )

      # Authorize either the existing preference or create a new one to check authorization
      authorize preference || EventPreference.new(user: current_user, preferenceable: @preferenceable)

      # Get resolved preferences with sources
      resolver = PreferenceResolver.new(current_user)
      resolved_data = resolver.resolve_with_sources(@preferenceable)

      # Generate preview with title, description, and location
      preview = generate_preview(resolved_data[:preferences])

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

      authorize preference

      if preference.update(event_preference_params)
        # Get resolved preferences with sources
        resolver = PreferenceResolver.new(current_user)
        resolved_data = resolver.resolve_with_sources(@preferenceable)

        # Generate preview with title, description, and location
        preview = generate_preview(resolved_data[:preferences])

        render json: {
          individual_preference: event_preference_json(preference),
          resolved: resolved_data[:preferences],
          sources: resolved_data[:sources],
          preview: preview
        }
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
        authorize preference
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
      params.expect(
        event_preference: [:title_template,
                           :description_template,
                           :location_template,
                           :color_id,
                           :visibility,
                           { reminder_settings: [] }]
      )
    end

    def event_preference_json(preference)
      {
        title_template: preference.title_template,
        description_template: preference.description_template,
        location_template: preference.location_template,
        reminder_settings: preference.reminder_settings,
        color_id: preference.color_id,
        visibility: preference.visibility
      }
    end

    def generate_preview(resolved_preferences)
      renderer = CalendarTemplateRenderer.new
      context = CalendarTemplateRenderer.build_context_from_meeting_time(@preferenceable)

      # Render title template
      title = if resolved_preferences[:title_template].present?
                renderer.render(resolved_preferences[:title_template], context)
              else
                context[:title]
              end

      # Render description template
      description = if resolved_preferences[:description_template].present?
                      renderer.render(resolved_preferences[:description_template], context)
                    else
                      ""
                    end

      # Render location template
      location = if resolved_preferences[:location_template].present?
                   renderer.render(resolved_preferences[:location_template], context)
                 else
                   context[:location] || ""
                 end

      {
        title: title,
        description: description,
        location: location
      }
    end

  end
end
