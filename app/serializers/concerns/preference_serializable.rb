# frozen_string_literal: true

module PreferenceSerializable
  private

  def transform_reminder_settings(reminder_settings)
    return nil if reminder_settings.nil?
    return [] if reminder_settings.empty?

    reminder_settings.map do |reminder|
      reminder = reminder.deep_symbolize_keys if reminder.is_a?(Hash)
      next reminder unless reminder.is_a?(Hash)

      reminder[:method] = "notification" if reminder[:method] == "popup"
      reminder.transform_keys(&:to_s)
    end
  end
end
