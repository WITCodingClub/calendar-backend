# frozen_string_literal: true

module MicrosoftGraph
  # Compares an Outlook event with the values the app last wrote to it, which
  # the calendar_events row keeps, and finds the fields the person changed.
  #
  # The rules follow GoogleCalendarService#detect_user_edited_fields: summary,
  # location, start time and end time count, and a changed recurrence keeps the
  # whole event as the person left it. The description does not count. Google
  # marks any description as an edit, but the row does not store the
  # description the app wrote, so that rule would freeze every description.
  class EventEdits
    # The fields a GET must ask for.
    SELECT          = "id,subject,location,start,end,isAllDay,recurrence"
    LOCAL_TIME_ZONE = "America/New_York"
    UTC_ZONES       = %w[UTC Etc/GMT GMT].freeze

    def initialize(row, remote)
      @row    = row
      @remote = remote || {}
    end

    def edited_fields
      fields = []
      fields << "summary"    if remote["subject"].to_s != row.summary.to_s
      fields << "location"   if remote.dig("location", "displayName").to_s != row.location.to_s
      fields << "start_time" if time_changed?(remote_start, row.start_time, all_day: all_day?)
      fields << "end_time"   if time_changed?(remote_end, row.end_time, all_day: all_day?)
      fields
    end

    def recurrence_changed?
      normalize(remote["recurrence"]) != normalize(EventPayload.recurrence_for(start_time: row.start_time, recurrence: row.recurrence))
    end

    # The event data with the person's value in place of each edited field.
    def merge(event_data, fields)
      merged = event_data.dup
      fields.each do |field|
        case field
        when "summary"    then merged[:summary]    = remote["subject"]
        when "location"   then merged[:location]   = remote.dig("location", "displayName")
        when "start_time" then merged[:start_time] = remote_start
        when "end_time"   then merged[:end_time]   = remote_end
        end
      end
      merged
    end

    # The row values that describe the event as the person left it.
    def remote_attributes
      { summary: remote["subject"], location: remote.dig("location", "displayName"),
        start_time: remote_start, end_time: remote_end }
    end

    private

    attr_reader :row, :remote

    def all_day?
      remote["isAllDay"] == true
    end

    def remote_start
      parse_time(remote["start"])
    end

    # An all-day event ends at midnight after its last day. The app keeps the
    # last day itself, like EventPayload expects.
    def remote_end
      time = parse_time(remote["end"])
      time && all_day? ? time - 1.day : time
    end

    def parse_time(value)
      return nil if value.blank? || value["dateTime"].blank?

      zone = UTC_ZONES.include?(value["timeZone"]) ? Time.find_zone!("UTC") : Time.find_zone!(LOCAL_TIME_ZONE)
      zone.parse(value["dateTime"])&.in_time_zone(LOCAL_TIME_ZONE)
    end

    def time_changed?(remote_time, row_time, all_day:)
      return remote_time != row_time if remote_time.nil? || row_time.nil?
      return remote_time.to_date != row_time.in_time_zone(LOCAL_TIME_ZONE).to_date if all_day

      remote_time.to_i != row_time.to_i
    end

    # Only the parts the app sets. Graph adds defaults such as dayOfMonth.
    def normalize(recurrence)
      return nil if recurrence.blank?

      recurrence = recurrence.deep_stringify_keys
      pattern    = recurrence["pattern"] || {}
      range      = recurrence["range"] || {}

      [
        pattern["type"], pattern["interval"].to_i, Array(pattern["daysOfWeek"]).sort,
        range["type"], range["type"] == "endDate" ? range["endDate"] : nil
      ]
    end
  end
end
