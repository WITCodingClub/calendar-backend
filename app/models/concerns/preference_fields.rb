# frozen_string_literal: true

# The preference fields that CalendarPreference and EventPreference share, and
# their rules. FIELDS is the one list of them: Preferences::Resolver,
# Preferences::Version and the change check below read it, and
# CalendarEvent.generate_data_hash hashes the event fields they produce.
module PreferenceFields
  extend ActiveSupport::Concern

  FIELDS = %i[title_template description_template location_template reminder_settings color_id visibility].freeze
  TEMPLATE_FIELDS = { title_template: 500, description_template: 2000, location_template: 500 }.freeze
  VISIBILITIES = %w[public private default].freeze

  # A reminder setting of [] means "no reminders", so only nil is unset. Any
  # other field is unset when blank.
  def self.set?(field, value)
    field == :reminder_settings ? !value.nil? : value.present?
  end

  included do
    TEMPLATE_FIELDS.each do |field, maximum|
      validates field, length: { maximum: maximum }, allow_blank: true
    end
    normalizes :color_id, with: Preferences::Colors.method(:normalize_attribute)
    validates :color_id, format: { with: Preferences::Colors::HEX_FORMAT }, allow_nil: true
    validates :visibility, inclusion: { in: VISIBILITIES }, allow_blank: true
    validate :validate_template_syntax

    # Stores "notification" as "popup" (Preferences::Reminders).
    before_validation :normalize_reminder_methods
    validate :validate_reminder_settings_format
  end

  def preference_fields_changed?
    FIELDS.any? { |field| saved_change_to_attribute?(field) }
  end

  def any_preference_set?
    FIELDS.any? { |field| PreferenceFields.set?(field, public_send(field)) }
  end

  private

  def validate_template_syntax
    TEMPLATE_FIELDS.each_key do |field|
      value = public_send(field)
      next if value.blank?

      Preferences::TemplateRenderer.validate_template(value)
    rescue Preferences::TemplateRenderer::InvalidTemplateError => e
      errors.add(field, "invalid syntax: #{e.message}")
    end
  end

  def normalize_reminder_methods
    return if reminder_settings.blank?
    return unless reminder_settings.is_a?(Array)

    self.reminder_settings = reminder_settings.map do |reminder|
      next reminder unless reminder.is_a?(Hash)

      stringified = reminder.stringify_keys
      stringified["method"] = Preferences::Reminders.stored_method(stringified["method"])
      stringified
    end
  end

  def validate_reminder_settings_format
    return if reminder_settings.blank?

    unless reminder_settings.is_a?(Array)
      errors.add(:reminder_settings, "must be an array")
      return
    end

    reminder_settings.each_with_index do |reminder, index|
      unless reminder.is_a?(Hash)
        errors.add(:reminder_settings, "item #{index} must be a hash")
        next
      end

      if reminder.key?("time")
        begin
          time_value = Float(reminder["time"])
          unless time_value.positive?
            errors.add(:reminder_settings, "item #{index} 'time' must be positive")
          end
        rescue ArgumentError, TypeError
          errors.add(:reminder_settings, "item #{index} 'time' must be a valid number")
        end
      else
        errors.add(:reminder_settings, "item #{index} must have 'time' field")
      end

      unless reminder.key?("type") && Preferences::Reminders::TIME_TYPES.include?(reminder["type"])
        errors.add(:reminder_settings, "item #{index} must have 'type' field (minutes, hours, or days)")
      end

      unless reminder.key?("method") && Preferences::Reminders::METHODS.include?(reminder["method"])
        errors.add(:reminder_settings, "item #{index} must have 'method' field (popup, notification, or email)")
      end
    end
  end
end
