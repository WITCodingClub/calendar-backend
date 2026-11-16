# frozen_string_literal: true

module Preferences
  # Finds the value of each preference field for one event. The most specific
  # row that sets a field wins: the event's own preference, then the
  # university category, the university wide row, the event type, and the
  # global row (lookup_path). A field that no row sets takes a default.
  class Resolver
    PREFERENCE_FIELDS = PreferenceFields::FIELDS

    SYSTEM_DEFAULTS = {
      title_template: "{% if schedule_type == 'Laboratory' %}{{title | remove: ' - Lab'}} - {{schedule_type_short}}{% else %}{{title}}{% endif %}",
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
      color_id: Preferences::Colors::TOMATO,
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
      color_id: Preferences::Colors::GRAPHITE,
      visibility: "default"
    }.freeze

    # Every default constant that resolve_field can return. Preferences::Version
    # hashes these, so a deploy that changes one gives each user a new version.
    # Add a new default constant here.
    def self.defaults
      [ SYSTEM_DEFAULTS, FINAL_EXAM_DEFAULTS, UNI_CAL_DEFAULTS, UNI_CAL_ALL_DAY_REMINDERS, UNI_CAL_TIMED_REMINDERS ]
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

    def resolve_actual_for(event)
      resolve_with_sources(event)[:preferences]
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
      rows << @user.user_extension_config unless university_calendar_event?(event)

      rows.compact.map(&:updated_at).max
    end

    private

    def preload_preferences(event_preferences, calendar_preferences)
      @event_preferences = (event_preferences || EventPreference.where(user: @user))
                           .index_by { |ep| [ ep.preferenceable_type, ep.preferenceable_id ] }

      @calendar_preferences = (calendar_preferences || CalendarPreference.where(user: @user))
                              .index_by { |cp| [ cp.scope, cp.event_type ] }

      @user.user_extension_config if @user.association(:user_extension_config).loaded? == false
    end

    def resolve_preferences(event)
      path = lookup_path(event)
      PREFERENCE_FIELDS.index_with { |field| resolve_field(event, field, path).first }
    end

    # The rows that apply to the event, most specific first, each with the
    # source name that resolve_with_sources gives.
    def lookup_path(event)
      event_type = extract_event_type(event)
      category   = extract_uni_cal_category(event)
      uni_cal    = university_calendar_event?(event)

      path = [ [ @event_preferences[[ event.class.name, event.id ]], "individual" ] ]
      path << [ @calendar_preferences[[ "uni_cal_category", category ]], "uni_cal_category:#{category}" ] if category.present?
      path << [ @calendar_preferences[[ "uni_cal_global", nil ]], "uni_cal_global" ] if uni_cal
      path << [ @calendar_preferences[[ "event_type", event_type ]], "event_type:#{event_type}" ] if event_type.present?
      path << [ @calendar_preferences[[ "global", nil ]], "global" ] unless uni_cal
      path
    end

    def resolve_field(event, field, path, ignore_dnd: false)
      return [ [], "dnd_override" ] if field == :reminder_settings && @notifications_disabled && !ignore_dnd

      path.each do |row, source|
        value = row&.public_send(field)
        return [ value, source ] if row && PreferenceFields.set?(field, value)
      end

      [ system_default_for(field, event, extract_event_type(event)), "system_default" ]
    end

    def extract_event_type(event)
      case event
      when FinalExam
        "final_exam"
      when Course::MeetingTime
        event.course&.schedule_type
      when CalendarEvent
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
      when CalendarEvent
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
end
