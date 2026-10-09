# frozen_string_literal: true

module GoogleCalendar
  # Turns the event hash the sync builds (the same one Microsoft gets) into a
  # Google::Apis::CalendarV3::Event.
  #
  # A custom color needs an event label. When the calendar cannot take labels,
  # the event gets the legacy colorId nearest to the color. Google reads
  # eventLabelId only when the request asks for label version 1, so pass
  # request_options(event) to insert_event and update_event.
  class EventPayload
    TIME_ZONE        = "America/New_York"
    REMINDER_METHODS = %w[email popup notification].freeze

    def self.build(event_data, labels = nil)
      new(event_data, labels).to_event
    end

    # With attendees: true the event lists the invited friends. Without, it
    # has none: an update replaces the whole event.
    def self.for_friend_meeting(meeting, attendees:)
      google_event = build(meeting.event_data)
      return google_event unless attendees

      google_event.attendees = meeting.invitees.map do |friend|
        Google::Apis::CalendarV3::EventAttendee.new(email: friend.email, display_name: friend.full_name)
      end
      google_event
    end

    # With label version 1, Google ignores colorId.
    def self.request_options(google_event)
      google_event.event_label_id.nil? ? {} : { event_label_version: 1 }
    end

    def initialize(event_data, labels = nil)
      @data   = event_data
      @labels = labels
    end

    def to_event
      google_event = Google::Apis::CalendarV3::Event.new(
        summary:     data[:summary],
        description: data[:description],
        location:    data[:location]
      )
      apply_color(google_event)
      apply_times(google_event)

      google_event.recurrence = data[:recurrence] if data[:recurrence].present?
      apply_reminders(google_event)
      google_event.visibility = data[:visibility] if data[:visibility].present?

      google_event
    end

    private

    attr_reader :data, :labels

    def apply_color(google_event)
      hex      = data[:color_id]
      label_id = labels.label_id_for(hex) if labels && hex

      if labels&.available? && (hex.nil? || label_id)
        # An empty id removes the label, so the event takes the calendar color.
        google_event.event_label_id = label_id.to_s
      elsif hex
        google_event.color_id = GoogleCalendar::Colors.nearest_color_id(hex).to_s
      end
    end

    def apply_times(google_event)
      if data[:all_day]
        google_event.start = { date: data[:start_time].to_date.to_s }
        google_event.end   = { date: (data[:end_time].to_date + 1.day).to_s }
      else
        start_time_et = data[:start_time].in_time_zone(TIME_ZONE)
        end_time_et   = data[:end_time].in_time_zone(TIME_ZONE)

        google_event.start = { date_time: start_time_et.iso8601, time_zone: TIME_ZONE }
        google_event.end   = { date_time: end_time_et.iso8601,   time_zone: TIME_ZONE }
      end
    end

    def apply_reminders(google_event)
      return unless data[:reminder_settings].is_a?(Array)

      valid_reminders = data[:reminder_settings].select { |reminder| valid_reminder?(reminder) }

      # An empty list means "no reminders". It must still send use_default: false,
      # otherwise Google applies the calendar default reminders.
      google_event.reminders = Google::Apis::CalendarV3::Event::Reminders.new(
        use_default: false,
        overrides:   valid_reminders.map do |reminder|
          method  = reminder["method"] == "notification" ? "popup" : reminder["method"]
          minutes = minutes_for(reminder["time"], reminder["type"])
          Google::Apis::CalendarV3::EventReminder.new(reminder_method: method, minutes: minutes)
        end
      )
    end

    def valid_reminder?(reminder)
      reminder.is_a?(Hash) &&
        reminder["method"].present? &&
        reminder["time"].present? &&
        reminder["type"].present? &&
        REMINDER_METHODS.include?(reminder["method"])
    end

    def minutes_for(time, type)
      time_value = time.to_f

      case type
      when "hours" then (time_value * 60).to_i
      when "days"  then (time_value * 1440).to_i
      else time_value.to_i
      end
    end
  end
end
