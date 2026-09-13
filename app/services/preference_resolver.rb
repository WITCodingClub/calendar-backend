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
    reminder_settings: [ { "time" => "30", "type" => "minutes", "method" => "popup" } ],
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

  # All-day events start at midnight, so "1 day before" fires at 12AM the day
  # before. 15 hours before start is 9AM the day before, which people read.
  UNI_CAL_ALL_DAY_REMINDERS = [ { "time" => "15", "type" => "hours", "method" => "popup" } ].freeze
  UNI_CAL_TIMED_REMINDERS   = [ { "time" => "30", "type" => "minutes", "method" => "popup" } ].freeze

  UNI_CAL_DEFAULTS = {
    title_template: "{{summary}}",
    description_template: "{{description}}",
    location_template: "{{location}}",
    reminder_settings: UNI_CAL_ALL_DAY_REMINDERS,
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
    @event_preferences[[ event.class.name, event.id ]]
  end

  private

  def preload_preferences
    @event_preferences = EventPreference.where(user: @user)
                                        .index_by { |ep| [ ep.preferenceable_type, ep.preferenceable_id ] }

    @calendar_preferences = CalendarPreference.where(user: @user)
                                              .index_by { |cp| [ cp.scope, cp.event_type ] }

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
      return [ [], "dnd_override" ]
    end

    event_pref = @event_preferences[[ event.class.name, event.id ]]
    if event_pref.present?
      value = event_pref.public_send(field)
      if field == :reminder_settings ? !value.nil? : value.present?
        return [ value, "individual" ]
      end
    end

    event_type = extract_event_type(event)
    uni_cal_category = extract_uni_cal_category(event)

    if uni_cal_category.present?
      cat_pref = @calendar_preferences[[ "uni_cal_category", uni_cal_category ]]
      if cat_pref.present?
        value = cat_pref.public_send(field)
        if field == :reminder_settings ? !value.nil? : value.present?
          return [ value, "uni_cal_category:#{uni_cal_category}" ]
        end
      end
    end

    if university_calendar_event?(event)
      uni_pref = @calendar_preferences[[ "uni_cal_global", nil ]]
      if uni_pref.present?
        value = uni_pref.public_send(field)
        if field == :reminder_settings ? !value.nil? : value.present?
          return [ value, "uni_cal_global" ]
        end
      end
    end

    if event_type.present?
      type_pref = @calendar_preferences[[ "event_type", event_type ]]
      if type_pref.present?
        value = type_pref.public_send(field)
        if field == :reminder_settings ? !value.nil? : value.present?
          return [ value, "event_type:#{event_type}" ]
        end
      end
    end

    global_pref = @calendar_preferences[[ "global", nil ]]
    if global_pref.present? && !university_calendar_event?(event)
      value = global_pref.public_send(field)
      if field == :reminder_settings ? !value.nil? : value.present?
        return [ value, "global" ]
      end
    end

    default_value = system_default_for(field, event, event_type)
    [ default_value, "system_default" ]
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
    university_calendar_event_for(event)&.category
  end

  def university_calendar_event?(event)
    university_calendar_event_for(event).present?
  end

  def university_calendar_event_for(event)
    case event
    when UniversityCalendarEvent
      event
    when GoogleCalendarEvent
      event.university_calendar_event
    end
  end

  def system_default_for(field, event, event_type)
    return FINAL_EXAM_DEFAULTS[field] if event_type == "final_exam"

    uni_cal_event = university_calendar_event_for(event)
    if uni_cal_event.present?
      return uni_cal_default_reminders(uni_cal_event) if field == :reminder_settings

      return UNI_CAL_DEFAULTS[field]
    end

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

  def uni_cal_default_reminders(uni_cal_event)
    uni_cal_event.all_day? ? UNI_CAL_ALL_DAY_REMINDERS : UNI_CAL_TIMED_REMINDERS
  end

  def cache_key_for(event)
    "#{event.class.name}:#{event.id}"
  end
end
