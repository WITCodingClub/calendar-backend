class ConvertReminderSettingsFormat < ActiveRecord::Migration[8.1]
  def up
    # Convert CalendarPreference reminder_settings
    CalendarPreference.find_each do |pref|
      next if pref.reminder_settings.blank?

      converted = convert_reminder_settings(pref.reminder_settings)
      pref.update_column(:reminder_settings, converted) if converted
    end

    # Convert EventPreference reminder_settings
    EventPreference.find_each do |pref|
      next if pref.reminder_settings.blank?

      converted = convert_reminder_settings(pref.reminder_settings)
      pref.update_column(:reminder_settings, converted) if converted
    end
  end

  def down
    # Convert CalendarPreference reminder_settings back
    CalendarPreference.find_each do |pref|
      next if pref.reminder_settings.blank?

      reverted = revert_reminder_settings(pref.reminder_settings)
      pref.update_column(:reminder_settings, reverted) if reverted
    end

    # Convert EventPreference reminder_settings back
    EventPreference.find_each do |pref|
      next if pref.reminder_settings.blank?

      reverted = revert_reminder_settings(pref.reminder_settings)
      pref.update_column(:reminder_settings, reverted) if reverted
    end
  end

  private

  def convert_reminder_settings(settings)
    return nil unless settings.is_a?(Array)

    settings.map do |reminder|
      next reminder unless reminder.is_a?(Hash)

      # Skip if already in new format
      next reminder if reminder.key?("time") && reminder.key?("type")

      # Convert old format to new format
      if reminder.key?("minutes")
        {
          "time" => reminder["minutes"].to_s,
          "type" => "minutes",
          "method" => reminder["method"]
        }
      else
        reminder
      end
    end
  end

  def revert_reminder_settings(settings)
    return nil unless settings.is_a?(Array)

    settings.map do |reminder|
      next reminder unless reminder.is_a?(Hash)

      # Skip if already in old format
      next reminder if reminder.key?("minutes")

      # Convert new format back to old format
      if reminder.key?("time") && reminder.key?("type")
        # Convert time and type back to minutes
        minutes = case reminder["type"]
                  when "minutes"
                    reminder["time"].to_i
                  when "hours"
                    reminder["time"].to_f * 60
                  when "days"
                    reminder["time"].to_f * 1440
                  else
                    reminder["time"].to_i
                  end

        {
          "minutes" => minutes.to_i,
          "method" => reminder["method"]
        }
      else
        reminder
      end
    end
  end
end
