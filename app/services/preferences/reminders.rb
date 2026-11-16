# frozen_string_literal: true

module Preferences
  # The rules for a reminder setting, a list of hashes such as
  # [{ "time" => "30", "type" => "minutes", "method" => "popup" }].
  #
  # "notification" is another name for "popup": old extension versions send it.
  # The preference models check a list against these rules
  # (ReminderSettingsNormalizable), and each provider sends the result of
  # .for_sync in its own form.
  module Reminders
    METHODS    = %w[popup notification email].freeze
    TIME_TYPES = %w[minutes hours days].freeze
    MINUTES    = { "minutes" => 1, "hours" => 60, "days" => 1440 }.freeze

    Reminder = Data.define(:delivery, :minutes)

    module_function

    # The reminders a provider sends, in the order of the list. An entry that
    # does not follow the rules is left out. Returns nil when the setting is not
    # a list: the provider then keeps its own default.
    def for_sync(settings)
      return nil unless settings.is_a?(Array)

      settings.filter_map do |reminder|
        next unless reminder.is_a?(Hash) && METHODS.include?(reminder["method"])
        next if reminder["time"].blank? || reminder["type"].blank?

        method = reminder["method"] == "notification" ? "popup" : reminder["method"]
        Reminder.new(delivery: method, minutes: (reminder["time"].to_f * MINUTES.fetch(reminder["type"], 1)).to_i)
      end
    end
  end
end
