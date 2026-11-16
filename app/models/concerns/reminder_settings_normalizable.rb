# frozen_string_literal: true

# Checks the reminder_settings column against Preferences::Reminders, and
# stores "notification" as "popup".
module ReminderSettingsNormalizable
  extend ActiveSupport::Concern

  included do
    before_validation :normalize_reminder_methods
    validate :validate_reminder_settings_format
  end

  private

  def normalize_reminder_methods
    return if reminder_settings.blank?
    return unless reminder_settings.is_a?(Array)

    self.reminder_settings = reminder_settings.map do |reminder|
      next reminder unless reminder.is_a?(Hash)

      stringified = reminder.stringify_keys
      stringified["method"] = "popup" if stringified["method"] == "notification"
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
