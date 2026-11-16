# frozen_string_literal: true

module Preferences
  # Finds the value of each preference field for one event. The most specific
  # row that sets a field wins: the event's own preference, then the
  # university category, the university wide row, the event type, and the
  # global row (lookup_path). A field that no row sets takes a default.
  class Resolver
    PREFERENCE_FIELDS = PreferenceFields::FIELDS

    # Every default that resolve_field can return. Preferences::Version
    # hashes these, so a deploy that changes one gives each user a new version.
    def self.defaults
      [ MeetingTimeContext::DEFAULTS, FinalExamContext::DEFAULTS, UniversityEventContext::DEFAULTS,
        UniversityEventContext::ALL_DAY_REMINDERS, UniversityEventContext::TIMED_REMINDERS ]
    end

    # A caller that resolves for many users at once can pass each user's
    # preference rows, loaded for all users in one query. Then this object
    # sends no query of its own.
    def initialize(user, event_preferences: nil, calendar_preferences: nil)
      @user = user
      @cache = {}
      @notifications_disabled = user.notifications_disabled?
      preload_preferences(event_preferences, calendar_preferences)
    end

    def notifications_disabled?
      @notifications_disabled
    end

    def resolve_for(event)
      cache_key = cache_key_for(event)
      return @cache[cache_key] if @cache.key?(cache_key)

      resolved = resolve_preferences(event)
      @cache[cache_key] = resolved
      resolved
    end

    def resolve_with_sources(event)
      path     = lookup_path(event)
      resolved = PREFERENCE_FIELDS.to_h { |field| [ field, resolve_field(event, field, path, ignore_dnd: true) ] }

      { preferences: resolved.transform_values(&:first), sources: resolved.transform_values(&:last) }
    end

    def get_event_preference(event)
      @event_preferences[[ event.class.name, event.id ]]
    end

    # The latest updated_at of the rows that resolve_for reads for this event:
    # the rows on its lookup path and the extension config (default colors).
    # Nil when no row applies. It uses only the preloaded rows, so it runs no
    # query. A deleted row cannot move it, so a removed preference shows only
    # with the next other change.
    def last_changed_at_for(event)
      rows = lookup_path(event).map(&:first)
      rows << @user.user_extension_config unless Context.for(event).university_event?

      rows.compact.map(&:updated_at).max
    end

    private

    def preload_preferences(event_preferences, calendar_preferences)
      @event_preferences = (event_preferences || EventPreference.where(user: @user))
                           .index_by { |ep| [ ep.preferenceable_type, ep.preferenceable_id ] }

      @calendar_preferences = (calendar_preferences || CalendarPreference.where(user: @user))
                              .index_by { |cp| [ cp.scope, cp.event_type ] }

      @config = @user.user_extension_config
    end

    def resolve_preferences(event)
      path = lookup_path(event)
      PREFERENCE_FIELDS.index_with { |field| resolve_field(event, field, path).first }
    end

    # The rows that apply to the event, most specific first, each with the
    # source name that resolve_with_sources gives.
    def lookup_path(event)
      context    = Context.for(event)
      event_type = context.event_type
      category   = context.university_category

      path = [ [ @event_preferences[[ event.class.name, event.id ]], "individual" ] ]
      path << [ @calendar_preferences[[ "uni_cal_category", category ]], "uni_cal_category:#{category}" ] if category.present?
      path << [ @calendar_preferences[[ "uni_cal_global", nil ]], "uni_cal_global" ] if context.university_event?
      path << [ @calendar_preferences[[ "event_type", event_type ]], "event_type:#{event_type}" ] if event_type.present?
      path << [ @calendar_preferences[[ "global", nil ]], "global" ] unless context.university_event?
      path
    end

    def resolve_field(event, field, path, ignore_dnd: false)
      return [ [], "dnd_override" ] if field == :reminder_settings && @notifications_disabled && !ignore_dnd

      path.each do |row, source|
        value = row&.public_send(field)
        return [ value, source ] if row && PreferenceFields.set?(field, value)
      end

      [ Context.for(event).default(field, @config), "system_default" ]
    end

    def cache_key_for(event)
      "#{event.class.name}:#{event.id}"
    end
  end
end
