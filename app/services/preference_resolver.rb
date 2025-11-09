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
    description_template: "{{faculty}} {{faculty_email}}",
    location_template: "{{building}} {{room}}",
    reminder_settings: [{ "minutes" => 30, "method" => "popup" }],
    color_id: nil, # Will use MeetingTime#event_color if not set
    visibility: "default"
  }.freeze

  def initialize(user)
    @user = user
    @cache = {}
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

  private

  def resolve_preferences(event)
    preferences = {}

    PREFERENCE_FIELDS.each do |field|
      preferences[field] = resolve_field(event, field).first
    end

    preferences
  end

  def resolve_field(event, field)
    # 1. Check individual event preference
    if event.respond_to?(:event_preference) && event.event_preference.present?
      value = event.event_preference.public_send(field)
      return [value, "individual"] if value.present?
    end

    # 2. Check for EventPreference record
    event_pref = EventPreference.find_by(user: @user, preferenceable: event)
    if event_pref.present?
      value = event_pref.public_send(field)
      return [value, "individual"] if value.present?
    end

    # 3. Check event-type preference (if event has a schedule_type or event_type)
    event_type = extract_event_type(event)
    if event_type.present?
      type_pref = CalendarPreference.find_by(
        user: @user,
        scope: :event_type,
        event_type: event_type
      )
      if type_pref.present?
        value = type_pref.public_send(field)
        return [value, "event_type:#{event_type}"] if value.present?
      end
    end

    # 4. Check global user preference
    global_pref = CalendarPreference.find_by(user: @user, scope: :global)
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
