# frozen_string_literal: true

# Provides validation and normalization for reminder_settings JSONB field
# Accepts both "popup" and "notification" as aliases (normalizes "notification" -> "popup" for Google Calendar API)
# Format: [{ "time": "30", "type": "minutes", "method": "popup" }]
module ReminderSettingsNormalizable
  extend ActiveSupport::Concern

  # Valid methods that users can input
  VALID_INPUT_METHODS = %w[popup notification email].freeze
  # Valid methods for Google Calendar API (notification gets normalized to popup)
  GOOGLE_CALENDAR_METHODS = %w[popup email].freeze
  # Valid time unit types
  VALID_TIME_TYPES = %w[minutes hours days].freeze

  included do
    before_validation :normalize_reminder_methods
    validate :validate_reminder_settings_format
  end

  private

  def normalize_reminder_methods
    return if reminder_settings.blank?
    return unless reminder_settings.is_a?(Array)

    reminder_settings.each do |reminder|
      next unless reminder.is_a?(Hash) && reminder["method"] == "notification"

      reminder["method"] = "popup"
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

      # Validate time field
      unless reminder.key?("time")
        errors.add(:reminder_settings, "item #{index} must have 'time' field")
      else
        # Validate that time can be converted to a number
        begin
          time_value = Float(reminder["time"])
          unless time_value.positive?
            errors.add(:reminder_settings, "item #{index} 'time' must be positive")
          end
        rescue ArgumentError, TypeError
          errors.add(:reminder_settings, "item #{index} 'time' must be a valid number")
        end
      end

      # Validate type field
      unless reminder.key?("type") && VALID_TIME_TYPES.include?(reminder["type"])
        errors.add(:reminder_settings, "item #{index} must have 'type' field (minutes, hours, or days)")
      end

      # Validate method field
      unless reminder.key?("method") && VALID_INPUT_METHODS.include?(reminder["method"])
        errors.add(:reminder_settings, "item #{index} must have 'method' field (popup, notification, or email)")
      end
    end
  end
end
