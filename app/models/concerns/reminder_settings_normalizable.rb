# frozen_string_literal: true

# Provides validation and normalization for reminder_settings JSONB field
# Accepts both "popup" and "notification" as aliases (normalizes "notification" -> "popup" for Google Calendar API)
module ReminderSettingsNormalizable
  extend ActiveSupport::Concern

  # Valid methods that users can input
  VALID_INPUT_METHODS = %w[popup notification email].freeze
  # Valid methods for Google Calendar API (notification gets normalized to popup)
  GOOGLE_CALENDAR_METHODS = %w[popup email].freeze

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

      unless reminder.key?("minutes") && reminder["minutes"].is_a?(Integer)
        errors.add(:reminder_settings, "item #{index} must have integer 'minutes' field")
      end

      unless reminder.key?("method") && VALID_INPUT_METHODS.include?(reminder["method"])
        errors.add(:reminder_settings, "item #{index} must have 'method' field (popup, notification, or email)")
      end
    end
  end
end
