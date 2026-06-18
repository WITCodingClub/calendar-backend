# frozen_string_literal: true

module Api
  class EventPreferencesController < ApiController
    include PreferenceParams

    before_action :set_preferenceable

    def show
      resolver       = PreferenceResolver.new(current_user)
      resolved_data  = resolver.resolve_with_sources(@preferenceable)
      preference     = resolver.get_event_preference(@preferenceable)

      authorize preference || EventPreference.new(user: current_user, preferenceable: @preferenceable)

      context        = CalendarTemplateRenderer.build_context_from_meeting_time(@preferenceable)
      preview        = generate_preview(resolved_data[:preferences], context)

      resolved_prefs = resolved_data[:preferences].dup
      resolved_prefs[:reminder_settings] = transform_reminder_settings(resolved_prefs[:reminder_settings])
      resolved_prefs[:color_id]          = normalize_color_to_witcc_hex(resolved_prefs[:color_id])

      render json: {
        individual_preference: preference ? EventPreferenceSerializer.new(preference).as_json : nil,
        resolved:              resolved_prefs,
        sources:               resolved_data[:sources],
        preview:               preview,
        templates:             context,
        notifications_disabled: resolver.notifications_disabled?
      }
    end

    def update
      resolver   = PreferenceResolver.new(current_user)
      preference = resolver.get_event_preference(@preferenceable)
      preference ||= EventPreference.new(user: current_user, preferenceable: @preferenceable)

      authorize preference

      if preference.update(event_preference_params)
        sync_updated_event

        fresh_resolver = PreferenceResolver.new(current_user)
        resolved_data  = fresh_resolver.resolve_with_sources(@preferenceable)
        context        = CalendarTemplateRenderer.build_context_from_meeting_time(@preferenceable)
        preview        = generate_preview(resolved_data[:preferences], context)

        resolved_prefs = resolved_data[:preferences].dup
        resolved_prefs[:reminder_settings] = transform_reminder_settings(resolved_prefs[:reminder_settings])
        resolved_prefs[:color_id]          = normalize_color_to_witcc_hex(resolved_prefs[:color_id])

        render json: {
          individual_preference: EventPreferenceSerializer.new(preference).as_json,
          resolved:              resolved_prefs,
          sources:               resolved_data[:sources],
          preview:               preview,
          templates:             context,
          notifications_disabled: fresh_resolver.notifications_disabled?
        }
      else
        render json: { errors: preference.errors.full_messages }, status: :unprocessable_content
      end
    end

    def destroy
      resolver   = PreferenceResolver.new(current_user)
      preference = resolver.get_event_preference(@preferenceable)

      if preference
        authorize preference
        preference.destroy
        sync_updated_event
        head :no_content
      else
        head :not_found
      end
    end

    private

    def set_preferenceable
      if params[:meeting_time_id]
        id    = params[:meeting_time_id]
        scope = Course::MeetingTime.eager_load(course: :faculties)
        @preferenceable = id.to_s.include?("_") ? scope.find_by_public_id!(id) : scope.find(id)
      elsif params[:google_calendar_event_id]
        id    = params[:google_calendar_event_id]
        scope = GoogleCalendarEvent.eager_load(meeting_time: { course: :faculties })
        @preferenceable = id.to_s.include?("_") ? scope.find_by_public_id!(id) : scope.find(id)
      else
        render json: { error: "Preferenceable not specified" }, status: :bad_request
      end
    end

    def sync_updated_event
      meeting_time = case @preferenceable
      when Course::MeetingTime   then @preferenceable
      when GoogleCalendarEvent   then @preferenceable.meeting_time
      end

      return unless meeting_time
      return unless current_user.google_credential

      GoogleCalendarSyncJob.perform_later(current_user, force: true)
    end

    def transform_reminder_settings(settings)
      return settings unless settings.is_a?(Array)

      settings.map do |r|
        r.is_a?(Hash) ? r.merge("method" => r["method"] == "popup" ? "notification" : r["method"]) : r
      end
    end

    def normalize_color_to_witcc_hex(color_id)
      return nil unless color_id

      GoogleColors::EVENT_MAP[color_id.to_i]
    end
  end
end
