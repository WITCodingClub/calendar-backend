# frozen_string_literal: true

module McpTools
  # Base for an MCP tool that changes data. It changes only the signed-in
  # user's own data, through the same models and policies as the matching
  # API endpoint. A write scope (McpTools::Scopes) is off by default on the
  # consent page, so the student turns each one on.
  #
  # The settings tools share the setting fields and their parsing here.
  class BaseWriteTool < BaseTool
    include PreferenceParams

    WRITE = {
      read_only_hint:   false,
      destructive_hint: false,
      idempotent_hint:  true,
      open_world_hint:  false
    }.freeze

    # The fields of a calendar or class setting, as the tools name them.
    SETTING_FIELDS = %w[title_template description_template location_template color visibility reminders].freeze

    TEMPLATE_HINT = "Liquid variables: #{Preferences::TemplateRenderer::ALLOWED_VARIABLES.map { |v| "{{#{v}}}" }.join(', ')}."

    SETTING_PROPERTIES = {
      title_template:       { type: "string", maxLength: 500, description: "The event title. #{TEMPLATE_HINT}" },
      description_template: { type: "string", maxLength: 2000, description: "The event description, same variables." },
      location_template:    { type: "string", maxLength: 500, description: "The event location, same variables." },
      color:                {
        type:        "string",
        description: "A color name (#{GoogleCalendar::Colors::NAMES.keys.join(', ')}), a Google Calendar " \
                     "color id from 1 to 11, or a #rrggbb hex color."
      },
      visibility:           { type: "string", enum: %w[default public private], description: "Who can see the event details." },
      reminders:            {
        type:        "array",
        maxItems:    5,
        description: "The reminders, which replace the current ones. An empty list means no reminders.",
        items:       {
          type:       "object",
          properties: {
            time:   { type: "number", exclusiveMinimum: 0 },
            type:   { type: "string", enum: %w[minutes hours days] },
            method: { type: "string", enum: %w[notification email] }
          },
          required:   %w[time type method]
        }
      },
      reset:                {
        type:        "array",
        items:       { type: "string", enum: SETTING_FIELDS },
        description: "Fields to remove from this level, so the level below applies again."
      }
    }.freeze

    class << self
      def inherited(subclass)
        super
        subclass.annotations(WRITE)
      end
    end

    private

    # PreferenceParams reads current_user.
    def current_user = user

    # A settings tool can create, change, or delete the row, so it checks each
    # policy method that applies before it changes anything.
    def authorize_change(preference)
      if preference.persisted?
        authorize preference, :update?
        authorize preference, :destroy?
      else
        authorize preference, :create?
      end
    end

    # Writes the setting arguments onto a preference row, then saves it. A row
    # with no field left is deleted, the same as the DELETE endpoint.
    # Returns :saved or :deleted.
    def apply_settings!(preference, arguments)
      preference.assign_attributes(setting_attributes(arguments))

      if setting_blank?(preference)
        preference.destroy! if preference.persisted?
        :deleted
      else
        preference.save || raise(ToolError, preference.errors.full_messages.to_sentence)
        :saved
      end
    end

    def setting_attributes(arguments)
      attributes = {}
      attributes[:title_template]       = arguments[:title_template] if arguments.key?(:title_template)
      attributes[:description_template] = arguments[:description_template] if arguments.key?(:description_template)
      attributes[:location_template]    = arguments[:location_template] if arguments.key?(:location_template)
      attributes[:color_id]             = parse_color(arguments[:color]) if arguments.key?(:color)
      attributes[:visibility]           = arguments[:visibility] if arguments.key?(:visibility)
      attributes[:reminder_settings]    = parse_reminders(arguments[:reminders]) if arguments.key?(:reminders)

      Array(arguments[:reset]).each do |field|
        raise ToolError, "reset takes #{SETTING_FIELDS.join(', ')}" unless SETTING_FIELDS.include?(field)

        attributes[column_for(field)] = nil
      end

      raise ToolError, "Pass at least one setting or reset." if attributes.empty?

      attributes
    end

    def column_for(field)
      case field
      when "color"     then :color_id
      when "reminders" then :reminder_settings
      else field.to_sym
      end
    end

    # A reminder list of [] means "no reminders", so only nil counts as unset.
    def setting_blank?(preference)
      %i[title_template description_template location_template color_id visibility].all? { |f| preference[f].blank? } &&
        preference.reminder_settings.nil?
    end

    def parse_color(value)
      name = value.to_s.strip.downcase
      GoogleCalendar::Colors::NAMES[name] || GoogleCalendar::Colors.normalize(name) ||
        raise(ToolError, "#{value.inspect} is not a color. Use a name (#{GoogleCalendar::Colors::NAMES.keys.join(', ')}), " \
                         "an id from 1 to 11, or #rrggbb.")
    end

    # The stored form, the same as the extension sends: string values, and
    # popup for a notification (ReminderSettingsNormalizable).
    def parse_reminders(reminders)
      raise ToolError, "reminders must be a list" unless reminders.is_a?(Array)

      reminders.map do |reminder|
        reminder = reminder.to_h.stringify_keys
        { "time" => reminder["time"].to_s, "type" => reminder["type"].to_s, "method" => reminder["method"].to_s }
      end
    end

    # The same rule as Api::EventPreferencesController: only a user with a
    # synced calendar needs a sync.
    def sync_calendar
      return unless user.google_credential || user.course_calendars.microsoft.exists?

      CourseCalendars::SyncJob.perform_later(user, force: true)
    end
  end
end
