# frozen_string_literal: true

module Api
  class EventPreferencesController < ApiController
    include PreferenceParams

    before_action :set_preferenceable, except: :batch_show

    def show
      render json: preference_payload(PreferenceResolver.new(current_user), @preferenceable)
    end

    MAX_BATCH_SIZE = 200

    # POST /api/meeting_times/preferences
    #
    # The same body as GET /api/meeting_times/:id/preference, for many meeting
    # times in one request, keyed by the id the caller sent. The calendar page
    # used to send one request per meeting time. Ids that match no meeting time
    # are listed in "missing", where the single endpoint answers 404.
    def batch_show
      ids = Array(params[:meeting_time_ids]).map(&:to_s).compact_blank.uniq

      if ids.empty?
        render json: { error: "meeting_time_ids is required" }, status: :bad_request
        return
      end

      if ids.size > MAX_BATCH_SIZE
        render json: { error: "At most #{MAX_BATCH_SIZE} meeting_time_ids per request" }, status: :bad_request
        return
      end

      record_ids    = ids.index_with { |id| meeting_time_record_id(id) }
      meeting_times = Course::MeetingTime.includes(course: [ :faculties, :term ], rooms: :building)
                                         .where(id: record_ids.values.compact)
                                         .index_by(&:id)
      resolver      = PreferenceResolver.new(current_user)

      preferences = {}
      missing     = []
      ids.each do |id|
        meeting_time = meeting_times[record_ids[id]]
        if meeting_time
          preferences[id] = preference_payload(resolver, meeting_time)
        else
          missing << id
        end
      end

      render json: { preferences: preferences, missing: missing }
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

    def preference_payload(resolver, preferenceable)
      resolved_data  = resolver.resolve_with_sources(preferenceable)
      preference     = resolver.get_event_preference(preferenceable)

      authorize preference || EventPreference.new(user: current_user, preferenceable: preferenceable), :show?

      context        = CalendarTemplateRenderer.build_context_from_meeting_time(preferenceable)
      preview        = generate_preview(resolved_data[:preferences], context)

      resolved_prefs = resolved_data[:preferences].dup
      resolved_prefs[:reminder_settings] = transform_reminder_settings(resolved_prefs[:reminder_settings])

      {
        individual_preference: preference ? EventPreferenceSerializer.new(preference).as_json : nil,
        resolved:              resolved_prefs,
        sources:               resolved_data[:sources],
        preview:               preview,
        templates:             context,
        notifications_disabled: resolver.notifications_disabled?
      }
    end

    # Reads an id the way Course::MeetingTime.find does: a public id with its
    # prefix, a bare hashid, or a database id. Returns nil for no match.
    def meeting_time_record_id(id)
      separator = EncodedIds.configuration.separator

      if id.include?(separator)
        prefix, _, hash = id.rpartition(separator)
        return nil unless prefix == Course::MeetingTime.get_public_id_prefix

        Course::MeetingTime.decode_id(hash)
      else
        Course::MeetingTime.decode_id(id) || Integer(id, exception: false)
      end
    end

    def set_preferenceable
      if params[:meeting_time_id]
        id    = params[:meeting_time_id]
        scope = Course::MeetingTime.eager_load(course: :faculties)
        @preferenceable = id.to_s.include?("_") ? scope.find_by_public_id!(id) : scope.find(id)
      elsif calendar_event_param
        id    = calendar_event_param
        scope = CalendarEvent.eager_load(meeting_time: { course: :faculties })
        @preferenceable = id.to_s.include?("_") ? scope.find_by_public_id!(id) : scope.find(id)
        # A CalendarEvent belongs to a specific user's calendar; enforce
        # ownership here so another user's event id can't leak preference data.
        authorize @preferenceable, :show?
      else
        render json: { error: "Preferenceable not specified" }, status: :bad_request
      end
    end

    def sync_updated_event
      meeting_time = case @preferenceable
      when Course::MeetingTime   then @preferenceable
      when CalendarEvent   then @preferenceable.meeting_time
      end

      return unless meeting_time
      return unless current_user.google_credential

      GoogleCalendarSyncJob.perform_later(current_user, force: true)
    end

    # calendar_event_id comes from /calendar_events/:id. The published extension
    # still calls the legacy /google_calendar_events/:id path.
    def calendar_event_param
      params[:calendar_event_id] || params[:google_calendar_event_id]
    end

    def transform_reminder_settings(settings)
      return settings unless settings.is_a?(Array)

      settings.map do |r|
        r.is_a?(Hash) ? r.merge("method" => r["method"] == "popup" ? "notification" : r["method"]) : r
      end
    end
  end
end
