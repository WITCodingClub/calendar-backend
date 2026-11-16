# frozen_string_literal: true

module MicrosoftGraph
  # Turns a CourseCalendars::Event into a Graph event resource, and a Graph
  # event back into a CourseCalendars::RemoteEvent.
  #
  # Graph has no RRULE or EXDATE. A daily, weekly, or monthly rule becomes a
  # patternedRecurrence, and the excluded days are cancelled after the series
  # exists (see MicrosoftGraph::CalendarProvider#cancel_excluded_occurrences).
  # Graph has one reminder per event, so the earliest reminder wins. Colors
  # are not part of the payload: MicrosoftGraph::CalendarProvider adds an
  # Outlook category.
  #
  # A timed event shows as busy, so a class in the primary calendar blocks the
  # time for people who check the person's availability. An all-day event, for
  # example a holiday, shows as free, like Outlook's own default.
  class EventPayload
    TIME_FORMAT     = "%Y-%m-%dT%H:%M:%S"
    # The fields a GET must ask for to read an event back.
    SELECT          = "id,subject,location,start,end,isAllDay,recurrence,categories"
    UTC_ZONES       = %w[UTC Etc/GMT GMT].freeze

    DAYS = {
      "SU" => "sunday", "MO" => "monday", "TU" => "tuesday", "WE" => "wednesday",
      "TH" => "thursday", "FR" => "friday", "SA" => "saturday"
    }.freeze

    # The ordinal in a monthly BYDAY, for example 2 in 2WE, as a Graph index.
    WEEK_INDEXES = { "1" => "first", "2" => "second", "3" => "third", "4" => "fourth", "-1" => "last" }.freeze

    SENSITIVITIES = %w[private confidential].freeze

    def self.build(event)
      new(event).to_h
    end

    # The patternedRecurrence of a CourseCalendars::Recurrence that starts at
    # start_time, or nil.
    def self.recurrence_payload(recurrence, start_time)
      return nil unless recurrence && start_time

      local_start = start_time.in_time_zone(SchoolTimeZone::NAME)
      pattern     = pattern_payload(recurrence, local_start)
      return nil unless pattern

      range = { startDate: local_start.to_date.iso8601, recurrenceTimeZone: MicrosoftGraph::TIME_ZONE }
      range = recurrence.until_date ? range.merge(type: "endDate", endDate: recurrence.until_date.iso8601) : range.merge(type: "noEnd")
      { pattern: pattern, range: range }
    end

    # A course sync builds only weekly rules. A friend meeting can also be
    # daily, or monthly on one weekday of the month.
    def self.pattern_payload(recurrence, local_start)
      interval = recurrence.interval

      case recurrence.frequency
      when "DAILY"
        { type: "daily", interval: interval }
      when "WEEKLY"
        days = recurrence.days.filter_map { |day| DAYS[day] }
        days = [ local_start.strftime("%A").downcase ] if days.empty?
        { type: "weekly", interval: interval, daysOfWeek: days, firstDayOfWeek: "sunday" }
      when "MONTHLY"
        match = recurrence.days.join(",").match(/\A(-?\d)([A-Z]{2})\z/)
        index = match && WEEK_INDEXES[match[1]]
        return nil unless index && DAYS[match[2]]

        { type: "relativeMonthly", interval: interval, daysOfWeek: [ DAYS[match[2]] ], index: index }
      end
    end

    # The Graph event as CourseCalendars::EventEdits reads it. row is the
    # tracking row of the event, and event_id the id the event has now.
    def self.remote_event(row, event_id, remote)
      CourseCalendars::RemoteEvent.new(
        id:                 event_id,
        summary:            remote["subject"],
        location:           remote.dig("location", "displayName"),
        start_time:         parse_time(remote["start"]),
        end_time:           parse_time(remote["end"]),
        all_day:            remote["isAllDay"] == true,
        recurrence_changed: normalize_recurrence(remote["recurrence"]) !=
                              normalize_recurrence(recurrence_payload(CourseCalendars::Recurrence.parse(row.recurrence), row.start_time)),
        raw:                remote
      )
    end
    def self.parse_time(value)
      return nil if value.blank? || value["dateTime"].blank?

      zone = UTC_ZONES.include?(value["timeZone"]) ? Time.find_zone!("UTC") : SchoolTimeZone.zone
      zone.parse(value["dateTime"])&.in_time_zone(SchoolTimeZone::NAME)
    end

    # Only the parts the app sets. Graph adds defaults such as dayOfMonth, and
    # an index for every type, so the index counts only for a relativeMonthly
    # pattern.
    def self.normalize_recurrence(recurrence)
      return nil if recurrence.blank?

      recurrence = recurrence.deep_stringify_keys
      pattern    = recurrence["pattern"] || {}
      range      = recurrence["range"] || {}

      [
        pattern["type"], pattern["interval"].to_i, Array(pattern["daysOfWeek"]).sort,
        pattern["type"] == "relativeMonthly" ? pattern["index"] : nil,
        range["type"], range["type"] == "endDate" ? range["endDate"] : nil
      ]
    end
    private_class_method :parse_time, :normalize_recurrence, :pattern_payload

    def initialize(event)
      @event = event
    end

    def to_h
      payload = {
        subject:    event.summary,
        body:       { contentType: "text", content: event.description.to_s },
        location:   { displayName: event.location.to_s },
        isAllDay:   all_day?,
        showAs:     all_day? ? "free" : "busy",
        start:      time_payload(start_value),
        end:        time_payload(end_value),
        recurrence: self.class.recurrence_payload(event.recurrence, event.start_time)
      }

      payload.merge!(reminder_payload)
      payload[:sensitivity] = SENSITIVITIES.include?(event.visibility) ? event.visibility : "normal" if event.visibility.present?
      payload
    end

    private

    attr_reader :event

    def all_day? = event.all_day?

    def local_start
      event.start_time.in_time_zone(SchoolTimeZone::NAME)
    end

    def start_value
      all_day? ? local_start.to_date.beginning_of_day.strftime(TIME_FORMAT) : local_start.strftime(TIME_FORMAT)
    end

    def end_value
      return event.exclusive_end_date.beginning_of_day.strftime(TIME_FORMAT) if all_day?

      event.end_time.in_time_zone(SchoolTimeZone::NAME).strftime(TIME_FORMAT)
    end

    def time_payload(value)
      { dateTime: value, timeZone: MicrosoftGraph::TIME_ZONE }
    end

    def reminder_payload
      reminders = Preferences::Reminders.for_sync(event.reminder_settings)
      return {} if reminders.nil?
      return { isReminderOn: false } if reminders.empty?

      { isReminderOn: true, reminderMinutesBeforeStart: reminders.map(&:minutes).min }
    end
  end
end
