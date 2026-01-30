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

      # Transform resolved preferences to alias "popup" to "notification" and convert color to WITCC hex
      resolved_prefs = resolved_data[:preferences].dup
      resolved_prefs[:reminder_settings] = transform_reminder_settings(resolved_prefs[:reminder_settings])
      resolved_prefs[:color_id] = normalize_color_to_witcc_hex(resolved_prefs[:color_id])

      render json: {
        individual_preference: preference ? event_preference_json(preference) : nil,
        resolved: resolved_prefs,
        sources: resolved_data[:sources],
        preview: preview,
        templates: context,
        notifications_disabled: resolver.notifications_disabled?
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

        # Create a fresh resolver after updating to get the latest preferences
        fresh_resolver = PreferenceResolver.new(current_user)
        resolved_data = fresh_resolver.resolve_with_sources(@preferenceable)

        # Build template context for preview and template values
        context = CalendarTemplateRenderer.build_context_from_meeting_time(@preferenceable)

        # Generate preview with title, description, and location
        preview = generate_preview(resolved_data[:preferences], context)

        # Transform resolved preferences to alias "popup" to "notification" and convert color to WITCC hex
        resolved_prefs = resolved_data[:preferences].dup
        resolved_prefs[:reminder_settings] = transform_reminder_settings(resolved_prefs[:reminder_settings])
        resolved_prefs[:color_id] = normalize_color_to_witcc_hex(resolved_prefs[:color_id])

        render json: {
          individual_preference: event_preference_json(preference),
          resolved: resolved_prefs,
          sources: resolved_data[:sources],
          preview: preview,
          templates: context,
          notifications_disabled: fresh_resolver.notifications_disabled?
        }
      else
        render json: { errors: preference.errors.full_messages }, status: :unprocessable_content
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
        # Accept both internal ID and public_id, use eager_load for associations
        @preferenceable = find_by_any_id!(MeetingTime, params[:meeting_time_id])
        @preferenceable = MeetingTime.eager_load(course: :faculties, room: :building).find(@preferenceable.id)
      elsif params[:google_calendar_event_id]
        # Accept both internal ID and public_id, use eager_load for associations
        @preferenceable = find_by_any_id!(GoogleCalendarEvent, params[:google_calendar_event_id])
        @preferenceable = GoogleCalendarEvent.eager_load(meeting_time: { course: :faculties, room: :building }).find(@preferenceable.id)
      else
        render json: { error: "Preferenceable not specified" }, status: :bad_request
      end
    end

    def event_preference_params
      # IMPORTANT: Use require/permit instead of expect due to Rails 8 bug
      # params.expect rejects empty arrays (e.g., reminder_settings: [])
      # See PR #294 and issues #290, #292 for details
      permitted = params.require(:event_preference).permit(
        :title_template,
        :description_template,
        :location_template,
        :color_id,
        :visibility,
        reminder_settings: []
      )
      # rubocop:enable Rails/StrongParametersExpect

      # If reminder_settings is present, manually permit the nested attributes
      if params[:event_preference][:reminder_settings].present?
        permitted[:reminder_settings] = params[:event_preference][:reminder_settings].map do |reminder|
          reminder.permit(:time, :method, :type)
        end
      elsif params[:event_preference].key?(:reminder_settings)
        # Explicitly set to empty array if key is present but value is empty
        permitted[:reminder_settings] = []
      end

      # Convert WITCC hex color to Google color ID if needed
      if permitted[:color_id].is_a?(String) && permitted[:color_id].start_with?("#")
        permitted[:color_id] = GoogleColors.witcc_to_color_id(permitted[:color_id])
      end

      permitted
    end

    def event_preference_json(preference)
      {
        title_template: preference.title_template,
        description_template: preference.description_template,
        location_template: preference.location_template,
        reminder_settings: transform_reminder_settings(preference.reminder_settings),
        color_id: normalize_color_to_witcc_hex(preference.color_id),
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

      # Sync this specific meeting time immediately (synchronously)
      return unless meeting_time

      # Check if user has Google credentials before attempting sync
      unless current_user.google_credential
        Rails.logger.warn "Cannot sync event preference - user #{current_user.id} has no Google credential"
        return
      end

      begin
        SyncMeetingTimeJob.perform_now(current_user.id, meeting_time.id)
        Rails.logger.info "Successfully synced event preference for user #{current_user.id}, meeting_time #{meeting_time.id}"
      rescue => e
        Rails.logger.error "Failed to sync event preference: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        # Don't raise - we don't want to fail the API request if sync fails
      end
    end

  end
end
