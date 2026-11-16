# frozen_string_literal: true

module McpTools
  # The calendar and class settings tools: the setting fields, their parsing,
  # and the confirmation message of a change.
  module SettingsTool
    # The fields of a calendar or class setting, as the tools name them.
    SETTING_FIELDS = %w[title_template description_template location_template color visibility reminders].freeze

    # The names of the setting columns in a confirmation message.
    FIELD_LABELS = {
      title_template:       "Event title",
      description_template: "Event description",
      location_template:    "Event location",
      color_id:             "Color",
      visibility:           "Visibility",
      reminder_settings:    "Reminders"
    }.freeze

    # A template in a confirmation message is escaped, so a newline cannot
    # change the layout, and cut to this length. Its lines come last.
    TEMPLATE_PREVIEW_LENGTH = 120
    TEMPLATE_COLUMNS = %i[title_template description_template location_template].freeze

    TEMPLATE_HINT = "Liquid variables: #{Preferences::TemplateRenderer::ALLOWED_VARIABLES.map { |v| "{{#{v}}}" }.join(', ')}. " \
                    "Tags: only {% if %} and {% unless %}, with elsif and else."

    SETTING_PROPERTIES = {
      title_template:       { type: "string", maxLength: 500, description: "The event title. #{TEMPLATE_HINT}" },
      description_template: { type: "string", maxLength: 2000, description: "The event description, same variables." },
      location_template:    { type: "string", maxLength: 500, description: "The event location, same variables." },
      color:                {
        type:        "string",
        description: "A color name (#{Preferences::Colors::NAMES.keys.join(', ')}), a Google Calendar " \
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

    private

    # The confirmation message of a settings change: what it affects, then one
    # line for each field that changes, with the template lines last, then the
    # extra lines (also changes) and the notes. Nil when nothing changes.
    def settings_message(target, preference, attributes, extra: [], notes: [])
      # The texts are compared, not the values: a stored "popup" reminder and
      # a new "notification" one are the same reminder.
      lines = attributes.partition { |column, _| !TEMPLATE_COLUMNS.include?(column) }.flatten(1).filter_map do |column, value|
        old = describe_setting(column, preference[column])
        updated = describe_setting(column, value)
        "- #{FIELD_LABELS.fetch(column)}: from #{old} to #{updated}." unless old == updated
      end
      lines += extra
      return if lines.empty?

      [ "Change the calendar events of #{target}:", *lines, *notes ].join("\n")
    end

    # Raises ToolError with the model's messages when the row cannot take the
    # attributes, so the student never confirms a change that cannot be saved.
    # The row keeps its values.
    def validate_settings!(preference, attributes)
      preference.assign_attributes(attributes)
      return if setting_blank?(preference) || preference.valid?

      raise ToolError, preference.errors.full_messages.to_sentence
    ensure
      preference.restore_attributes(attributes.keys.map(&:to_s))
      preference.errors.clear
    end

    def describe_setting(column, value)
      return "not set" if value.nil?

      case column
      when :color_id then Preferences::Colors::NAMES.key(value)&.capitalize || escape_text(value)
      when :reminder_settings then describe_reminders(value)
      when :visibility then escape_text(value)
      else value.to_s.empty? ? "empty" : %("#{escape_text(value)}")
      end
    end

    # One line of plain text: control characters as escapes, cut to
    # TEMPLATE_PREVIEW_LENGTH characters.
    def escape_text(value)
      text = value.to_s
      text = "#{text[0, TEMPLATE_PREVIEW_LENGTH]}..." if text.length > TEMPLATE_PREVIEW_LENGTH
      text.gsub(/[\\"[:cntrl:]]/) do |char|
        { "\\" => "\\\\", '"' => '\"', "\n" => "\\n", "\r" => "\\r", "\t" => "\\t" }.fetch(char) { format("\\u%04x", char.ord) }
      end
    end

    def describe_reminders(reminders)
      return "no reminders" if reminders.empty?

      reminders.map do |reminder|
        reminder = reminder.to_h.stringify_keys
        time     = describe_number(reminder["time"])
        type     = escape_text(reminder["type"])
        type     = type.singularize if time == "1"
        method   = reminder["method"] == "email" ? "email" : "notification"
        "#{time} #{type} before by #{method}"
      end.join(", ")
    end

    # "1.0" as "1", "1.50" as "1.5". Anything that is not a number stays as text.
    def describe_number(value)
      number = Float(value.to_s, exception: false)
      return escape_text(value) if number.nil?

      number == number.to_i ? number.to_i.to_s : number.to_s
    end

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

    # Writes the attributes (from setting_attributes) onto a preference row,
    # then saves it. A row with no field left is deleted, the same as the
    # DELETE endpoint. Returns :saved or :deleted.
    def apply_settings!(preference, attributes)
      preference.assign_attributes(attributes)

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
      Preferences::Colors::NAMES[name] || Preferences::Colors.normalize(name) ||
        raise(ToolError, "#{value.inspect} is not a color. Use a name (#{Preferences::Colors::NAMES.keys.join(', ')}), " \
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

    # Only a user with a synced calendar needs a sync.
    def sync_calendar
      return unless user.google_credential || user.course_calendars.microsoft.exists?

      CourseCalendars::SyncJob.perform_later(user, force: true)
    end
  end
end
