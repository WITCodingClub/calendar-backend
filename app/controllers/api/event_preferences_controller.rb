# frozen_string_literal: true

module Api
  class EventPreferencesController < ApiController
    before_action :set_preferenceable

    # GET /api/meeting_times/:meeting_time_id/preference
    # GET /api/google_calendar_events/:google_calendar_event_id/preference
    def show
      # Get resolved preferences with sources (PreferenceResolver preloads all EventPreferences)
      resolver = PreferenceResolver.new(current_user)
      resolved_data = resolver.resolve_with_sources(@preferenceable)

      # Get individual preference from resolver's preloaded data instead of separate query
      preference = resolver.get_event_preference(@preferenceable)

      # Authorize either the existing preference or create a new one to check authorization
      authorize preference || EventPreference.new(user: current_user, preferenceable: @preferenceable)

      # Build template context for preview and template values
      context = CalendarTemplateRenderer.build_context_from_meeting_time(@preferenceable)

      # Generate preview with title, description, and location
      preview = generate_preview(resolved_data[:preferences], context)

      # Transform resolved preferences to alias "popup" to "notification"
      resolved_prefs = resolved_data[:preferences].dup
      resolved_prefs[:reminder_settings] = transform_reminder_settings(resolved_prefs[:reminder_settings])

      render json: {
        individual_preference: preference ? event_preference_json(preference) : nil,
        resolved: resolved_prefs,
        sources: resolved_data[:sources],
        preview: preview,
        templates: context
      }
    end

    # PUT /api/meeting_times/:meeting_time_id/preference
    # PUT /api/google_calendar_events/:google_calendar_event_id/preference
    def update
      # Get resolved preferences with sources (PreferenceResolver preloads all EventPreferences)
      resolver = PreferenceResolver.new(current_user)

      # Get individual preference from resolver's preloaded data instead of separate query
      preference = resolver.get_event_preference(@preferenceable)
      preference ||= EventPreference.new(user: current_user, preferenceable: @preferenceable)

      authorize preference

      if preference.update(event_preference_params)
        # Trigger immediate sync for this specific event
        sync_updated_event

        resolved_data = resolver.resolve_with_sources(@preferenceable)

        # Build template context for preview and template values
        context = CalendarTemplateRenderer.build_context_from_meeting_time(@preferenceable)

        # Generate preview with title, description, and location
        preview = generate_preview(resolved_data[:preferences], context)

        # Transform resolved preferences to alias "popup" to "notification"
        resolved_prefs = resolved_data[:preferences].dup
        resolved_prefs[:reminder_settings] = transform_reminder_settings(resolved_prefs[:reminder_settings])

        render json: {
          individual_preference: event_preference_json(preference),
          resolved: resolved_prefs,
          sources: resolved_data[:sources],
          preview: preview,
          templates: context
        }
      else
        render json: { errors: preference.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # DELETE /api/meeting_times/:meeting_time_id/preference
    # DELETE /api/google_calendar_events/:google_calendar_event_id/preference
    def destroy
      # Create resolver to get preloaded EventPreferences
      resolver = PreferenceResolver.new(current_user)
      preference = resolver.get_event_preference(@preferenceable)

      if preference
        authorize preference
        preference.destroy

        # Trigger immediate sync for this specific event
        sync_updated_event

        head :no_content
      else
        head :not_found
      end
    end

    private

    def set_preferenceable
      if params[:meeting_time_id]
        # Use eager_load to force LEFT OUTER JOINs (single query) instead of separate SELECTs
        @preferenceable = MeetingTime.eager_load(course: :faculties, room: :building).find(params[:meeting_time_id])
      elsif params[:google_calendar_event_id]
        # Use eager_load for GoogleCalendarEvent as well
        @preferenceable = GoogleCalendarEvent.eager_load(meeting_time: { course: :faculties, room: :building }).find(params[:google_calendar_event_id])
      else
        render json: { error: "Preferenceable not specified" }, status: :bad_request
      end
    end

    def event_preference_params
      params.require(:event_preference).permit(
        :title_template,
        :description_template,
        :location_template,
        :color_id,
        :visibility,
        reminder_settings: [:time, :method, :type]
      )
    end

    def event_preference_json(preference)
      {
        title_template: preference.title_template,
        description_template: preference.description_template,
        location_template: preference.location_template,
        reminder_settings: transform_reminder_settings(preference.reminder_settings),
        color_id: preference.color_id,
        visibility: preference.visibility
      }
    end

    def generate_preview(resolved_preferences, context)
      renderer = CalendarTemplateRenderer.new

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

    def sync_updated_event
      # Get the meeting_time from the preferenceable
      meeting_time = if @preferenceable.is_a?(MeetingTime)
                       @preferenceable
                     elsif @preferenceable.is_a?(GoogleCalendarEvent)
                       @preferenceable.meeting_time
                     end

      # Sync just this specific meeting time in the background
      if meeting_time
        SyncMeetingTimeJob.perform_later(current_user.id, meeting_time.id)
      end
    end

  end
end
