# frozen_string_literal: true

module GoogleCalendar
  # Turns the event hash the sync builds (the same one Microsoft gets) into a
  # Google::Apis::CalendarV3::Event, and a Google event back into a
  # CourseCalendars::RemoteEvent.
  #
  # A custom color needs an event label. When the calendar cannot take labels,
  # the event gets the legacy colorId nearest to the color. Google reads
  # eventLabelId only when the request asks for label version 1, so pass
  # request_options(event) to insert_event and update_event.
  class EventPayload

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

    # The Google event as CourseCalendars::EventEdits reads it. row is the
    # tracking row of the event.
    def self.remote_event(row, google_event)
      CourseCalendars::RemoteEvent.new(
        id:                 row.external_event_id,
        summary:            google_event.summary,
        location:           google_event.location,
        start_time:         parse_time(google_event.start),
        end_time:           parse_time(google_event.end),
        all_day:            google_event.start&.date.present?,
        recurrence_changed: normalize_recurrence(google_event.recurrence) != normalize_recurrence(row.recurrence),
        raw:                google_event
      )
    end

    # A Google EventDateTime as a time in SchoolTimeZone, or nil.
    def self.parse_time(time_obj)
      value = time_obj&.date_time || time_obj&.date
      return nil unless value

      value.is_a?(String) ? Time.zone.parse(value).in_time_zone(SchoolTimeZone::NAME) : value.in_time_zone(SchoolTimeZone::NAME)
    end

    def self.normalize_recurrence(recurrence)
      Array(recurrence).compact.sort.presence
    end
    private_class_method :parse_time, :normalize_recurrence

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
        google_event.color_id = Preferences::Colors.nearest_color_id(hex).to_s
      end
    end

    def apply_times(google_event)
      if data[:all_day]
        google_event.start = { date: data[:start_time].to_date.to_s }
        google_event.end   = { date: (data[:end_time].to_date + 1.day).to_s }
      else
        start_time_et = data[:start_time].in_time_zone(SchoolTimeZone::NAME)
        end_time_et   = data[:end_time].in_time_zone(SchoolTimeZone::NAME)

        google_event.start = { date_time: start_time_et.iso8601, time_zone: SchoolTimeZone::NAME }
        google_event.end   = { date_time: end_time_et.iso8601,   time_zone: SchoolTimeZone::NAME }
      end
    end

    def apply_reminders(google_event)
      reminders = Preferences::Reminders.for_sync(data[:reminder_settings])
      return if reminders.nil?

      # An empty list means "no reminders". It must still send use_default: false,
      # otherwise Google applies the calendar default reminders.
      google_event.reminders = Google::Apis::CalendarV3::Event::Reminders.new(
        use_default: false,
        overrides:   reminders.map do |reminder|
          Google::Apis::CalendarV3::EventReminder.new(reminder_method: reminder.delivery, minutes: reminder.minutes)
        end
      )
    end
  end
end
