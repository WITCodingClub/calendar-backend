# frozen_string_literal: true

class PreferenceResolver
  PREFERENCE_FIELDS = %i[
    title_template
    description_template
    location_template
    reminder_settings
    color_id
    visibility
  ].freeze

  SYSTEM_DEFAULTS = {
    title_template: "{{class_name}}",
    description_template: "{{faculty}}\n{{faculty_email}}",
    location_template: "{{building}} {{room}}",
    reminder_settings: [{ "minutes" => 30, "method" => "popup" }],
    color_id: nil, # Will use MeetingTime#event_color if not set
    visibility: "default"
  }.freeze

  def initialize(user)
    @user = user
    @cache = {}
    # Preload all preferences to avoid N+1 queries
    preload_preferences
  end

  # Resolve preferences for a MeetingTime or GoogleCalendarEvent
  def resolve_for(event)
    cache_key = cache_key_for(event)
    return @cache[cache_key] if @cache.key?(cache_key)

    resolved = resolve_preferences(event)
    @cache[cache_key] = resolved
    resolved
  end

  # Resolve and return source information for debugging/UI
  def resolve_with_sources(event)
    preferences = {}
    sources = {}

    PREFERENCE_FIELDS.each do |field|
      value, source = resolve_field(event, field)
      preferences[field] = value
      sources[field] = source
    end

    { preferences: preferences, sources: sources }
  end

  # Get a specific EventPreference from preloaded data
  def get_event_preference(event)
    @event_preferences[[event.class.name, event.id]]
  end

  private

  def preload_preferences
    # Load all EventPreferences for this user, indexed by preferenceable_type and preferenceable_id
    @event_preferences = EventPreference.where(user: @user)
                                        .index_by { |ep| [ep.preferenceable_type, ep.preferenceable_id] }

    # Load all CalendarPreferences for this user, indexed by scope and event_type
    @calendar_preferences = CalendarPreference.where(user: @user)
                                              .index_by { |cp| [cp.scope, cp.event_type] }
  end

  def resolve_preferences(event)
    preferences = {}

    PREFERENCE_FIELDS.each do |field|
      preferences[field] = resolve_field(event, field).first
    end

    preferences
  end

  def resolve_field(event, field)
    # 1. Check for EventPreference record (use preloaded data)
    # This replaces the old event.event_preference check which would trigger a query
    event_pref = @event_preferences[[event.class.name, event.id]]
    if event_pref.present?
      value = event_pref.public_send(field)
      return [value, "individual"] if value.present?
    end

    # 3. Check event-type preference (use preloaded data)
    event_type = extract_event_type(event)
    if event_type.present?
      type_pref = @calendar_preferences[["event_type", event_type]]
      if type_pref.present?
        value = type_pref.public_send(field)
        return [value, "event_type:#{event_type}"] if value.present?
      end
    end

    # 4. Check global user preference (use preloaded data)
    global_pref = @calendar_preferences[["global", nil]]
    if global_pref.present?
      value = global_pref.public_send(field)
      return [value, "global"] if value.present?
    end

    # 5. Use system defaults
    default_value = system_default_for(field, event_type)
    [default_value, "system_default"]
  end

  def extract_event_type(event)
    case event
    when MeetingTime
      event.course&.schedule_type
    when GoogleCalendarEvent
      # If GoogleCalendarEvent has meeting_time, use its schedule_type
      event.meeting_time&.course&.schedule_type
    else
      nil
    end
  end

  def system_default_for(field, event_type)
    SYSTEM_DEFAULTS[field]
  end

  def cache_key_for(event)
    "#{event.class.name}:#{event.id}"
  end

end
