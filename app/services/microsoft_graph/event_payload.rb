# frozen_string_literal: true

module MicrosoftGraph
  # Turns the event hash the sync builds (the same one Google gets) into a
  # Graph event resource.
  #
  # Graph has no RRULE or EXDATE. A weekly RRULE becomes a patternedRecurrence,
  # and the EXDATE days are cancelled after the series exists (see
  # MicrosoftGraphCalendarService#cancel_excluded_occurrences). Graph has one
  # reminder per event, so the earliest reminder wins. Event colors are not
  # sent: Outlook colors come from categories, not a color id.
  class EventPayload
    GRAPH_TIME_ZONE = "Eastern Standard Time"
    LOCAL_TIME_ZONE = "America/New_York"
    TIME_FORMAT     = "%Y-%m-%dT%H:%M:%S"

    DAYS = {
      "SU" => "sunday", "MO" => "monday", "TU" => "tuesday", "WE" => "wednesday",
      "TH" => "thursday", "FR" => "friday", "SA" => "saturday"
    }.freeze

    REMINDER_METHODS = %w[email popup notification].freeze
    SENSITIVITY      = { "private" => "private", "confidential" => "confidential" }.freeze

    def self.build(event_data)
      new(event_data).to_h
    end

    # The local dates an EXDATE list removes from a series.
    def self.excluded_dates(recurrence)
      Array(recurrence).select { |rule| rule.to_s.start_with?("EXDATE") }.flat_map do |rule|
        rule.split(":", 2).last.to_s.split(",").filter_map do |value|
          Date.strptime(value[0, 8], "%Y%m%d")
        rescue Date::Error
          nil
        end
      end.uniq
    end

    def initialize(event_data)
      @data = event_data
    end

    def to_h
      payload = {
        subject:    data[:summary],
        body:       { contentType: "text", content: data[:description].to_s },
        location:   { displayName: data[:location].to_s },
        isAllDay:   all_day?,
        start:      time_payload(start_value),
        end:        time_payload(end_value),
        recurrence: recurrence_payload
      }

      payload.merge!(reminder_payload)
      payload[:sensitivity] = SENSITIVITY.fetch(data[:visibility], "normal") if data[:visibility].present?
      payload
    end

    private

    attr_reader :data

    def all_day?
      data[:all_day] ? true : false
    end

    def local_start
      data[:start_time].in_time_zone(LOCAL_TIME_ZONE)
    end

    def start_value
      all_day? ? local_start.to_date.beginning_of_day.strftime(TIME_FORMAT) : local_start.strftime(TIME_FORMAT)
    end

    # An all-day event ends at midnight on the day after, like Google's
    # exclusive end date.
    def end_value
      local_end = data[:end_time].in_time_zone(LOCAL_TIME_ZONE)
      all_day? ? (local_end.to_date + 1.day).beginning_of_day.strftime(TIME_FORMAT) : local_end.strftime(TIME_FORMAT)
    end

    def time_payload(value)
      { dateTime: value, timeZone: GRAPH_TIME_ZONE }
    end

    def recurrence_payload
      rule = Array(data[:recurrence]).find { |entry| entry.to_s.start_with?("RRULE:") }
      return nil unless rule

      parts = rule.delete_prefix("RRULE:").split(";").to_h { |part| part.split("=", 2) }
      # The sync only builds weekly rules.
      return nil unless parts["FREQ"] == "WEEKLY"

      start_date = local_start.to_date
      days = parts["BYDAY"].to_s.split(",").filter_map { |day| DAYS[day] }
      days = [ start_date.strftime("%A").downcase ] if days.empty?

      {
        pattern: {
          type:           "weekly",
          interval:       (parts["INTERVAL"] || 1).to_i,
          daysOfWeek:     days,
          firstDayOfWeek: "sunday"
        },
        range: range_payload(parts["UNTIL"], start_date)
      }
    end

    def range_payload(until_value, start_date)
      range = { startDate: start_date.iso8601, recurrenceTimeZone: GRAPH_TIME_ZONE }
      return range.merge(type: "noEnd") if until_value.blank?

      end_date = Time.parse(until_value).in_time_zone(LOCAL_TIME_ZONE).to_date
      range.merge(type: "endDate", endDate: end_date.iso8601)
    end

    def reminder_payload
      settings = data[:reminder_settings]
      return {} unless settings.is_a?(Array)

      minutes = settings.filter_map do |reminder|
        next unless reminder.is_a?(Hash) && REMINDER_METHODS.include?(reminder["method"])
        next if reminder["time"].blank? || reminder["type"].blank?

        to_minutes(reminder["time"], reminder["type"])
      end

      return { isReminderOn: false } if minutes.empty?

      { isReminderOn: true, reminderMinutesBeforeStart: minutes.min }
    end

    def to_minutes(time, type)
      value = time.to_f

      case type
      when "hours" then (value * 60).to_i
      when "days"  then (value * 1440).to_i
      else value.to_i
      end
    end
  end
end
