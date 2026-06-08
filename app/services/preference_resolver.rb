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
    title_template: "{{title}}",
    description_template: "{{faculty}}\n{{faculty_email}}",
    location_template: "{{building}} {{room}}",
    reminder_settings: [{ "time" => "30", "type" => "minutes", "method" => "popup" }],
    color_id: nil,
    visibility: "default"
  }.freeze

  FINAL_EXAM_DEFAULTS = {
    title_template: "Final Exam: {{title}}",
    description_template: "{{course_code}}\n{{faculty}}",
    location_template: "{{location}}",
    reminder_settings: [
      { "time" => "1", "type" => "days", "method" => "popup" },
      { "time" => "1", "type" => "hours", "method" => "popup" },
      { "time" => "15", "type" => "minutes", "method" => "popup" }
    ],
    color_id: 11,
    visibility: "default"
  }.freeze

  UNI_CAL_DEFAULTS = {
    title_template: "{{summary}}",
    description_template: "{{description}}",
    location_template: "{{location}}",
    reminder_settings: [{ "time" => "1", "type" => "days", "method" => "popup" }],
    color_id: 8,
    visibility: "default"
  }.freeze

  def initialize(user)
    @user = user
    @cache = {}
    @notifications_disabled = user.notifications_disabled?
    preload_preferences
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

  def resolve_actual_for(event)
    preferences = {}

    PREFERENCE_FIELDS.each do |field|
      preferences[field] = resolve_field(event, field, ignore_dnd: true).first
    end

    preferences
  end

  def resolve_with_sources(event)
    preferences = {}
    sources = {}

    PREFERENCE_FIELDS.each do |field|
      value, source = resolve_field(event, field, ignore_dnd: true)
      preferences[field] = value
      sources[field] = source
    end

    { preferences: preferences, sources: sources }
  end

  def get_event_preference(event)
    @event_preferences[[event.class.name, event.id]]
  end

  private

  def preload_preferences
    @event_preferences = EventPreference.where(user: @user)
                                        .index_by { |ep| [ep.preferenceable_type, ep.preferenceable_id] }

    @calendar_preferences = CalendarPreference.where(user: @user)
                                              .index_by { |cp| [cp.scope, cp.event_type] }

    @user.user_extension_config if @user.association(:user_extension_config).loaded? == false
  end

  def resolve_preferences(event)
    preferences = {}

    PREFERENCE_FIELDS.each do |field|
      preferences[field] = resolve_field(event, field).first
    end

    preferences
  end

  def resolve_field(event, field, ignore_dnd: false)
    if field == :reminder_settings && @notifications_disabled && !ignore_dnd
      return [[], "dnd_override"]
    end

    event_pref = @event_preferences[[event.class.name, event.id]]
    if event_pref.present?
      value = event_pref.public_send(field)
      if field == :reminder_settings ? !value.nil? : value.present?
        return [value, "individual"]
      end
    end

    event_type = extract_event_type(event)
    uni_cal_category = extract_uni_cal_category(event)

    if uni_cal_category.present?
      cat_pref = @calendar_preferences[["uni_cal_category", uni_cal_category]]
      if cat_pref.present?
        value = cat_pref.public_send(field)
        if field == :reminder_settings ? !value.nil? : value.present?
          return [value, "uni_cal_category:#{uni_cal_category}"]
        end
      end
    end

    if event_type.present?
      type_pref = @calendar_preferences[["event_type", event_type]]
      if type_pref.present?
        value = type_pref.public_send(field)
        if field == :reminder_settings ? !value.nil? : value.present?
          return [value, "event_type:#{event_type}"]
        end
      end
    end

    global_pref = @calendar_preferences[["global", nil]]
    if global_pref.present?
      value = global_pref.public_send(field)
      if field == :reminder_settings ? !value.nil? : value.present?
        return [value, "global"]
      end
    end

    default_value = system_default_for(field, event, event_type, uni_cal_category)
    [default_value, "system_default"]
  end

  def extract_event_type(event)
    case event
    when FinalExam
      "final_exam"
    when Course::MeetingTime
      event.course&.schedule_type
    when GoogleCalendarEvent
      return "final_exam" if event.final_exam_id.present?

      event.meeting_time&.course&.schedule_type
    end
  end

  def extract_uni_cal_category(event)
    case event
    when UniversityCalendarEvent
      event.category
    when GoogleCalendarEvent
      event.university_calendar_event&.category
    end
  end

  def system_default_for(field, event, event_type, uni_cal_category = nil)
    return FINAL_EXAM_DEFAULTS[field] if event_type == "final_exam"

    return UNI_CAL_DEFAULTS[field] if uni_cal_category.present?

    if field == :color_id
      meeting_time = event.is_a?(Course::MeetingTime) ? event : event.meeting_time

      if @user.user_extension_config.present? && event_type.present?
        color = case event_type
                when "lecture"
                  @user.user_extension_config.default_color_lecture
                when "laboratory"
                  @user.user_extension_config.default_color_lab
                end
        return color if color.present?
      end

      return meeting_time&.event_color
    end

    SYSTEM_DEFAULTS[field]
  end

  def cache_key_for(event)
    "#{event.class.name}:#{event.id}"
  end
end
