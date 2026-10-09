# frozen_string_literal: true

module GoogleCalendar
  # Compares a Google Calendar event with the values the app last wrote to it,
  # which the calendar_events row keeps, and finds the fields the person changed.
  #
  # Summary, location, start time and end time count when they differ. Any
  # description counts as an edit. A changed recurrence keeps the whole event
  # as the person left it. MicrosoftGraph::EventEdits follows the same rules.
  class EventEdits
    TIME_ZONE = "America/New_York"

    # A Google EventDateTime as a time in TIME_ZONE, or nil.
    def self.parse_time(time_obj)
      return nil unless time_obj

      value = time_obj.date_time || time_obj.date
      return nil unless value

      value.is_a?(String) ? Time.zone.parse(value).in_time_zone(TIME_ZONE) : value.in_time_zone(TIME_ZONE)
    end

    def self.normalize_recurrence(recurrence)
      return nil if recurrence.blank?

      Array(recurrence).compact.sort
    end

    def initialize(row, remote)
      @row    = row
      @remote = remote
    end

    def edited_fields
      fields = []

      fields << "summary"     if remote.summary  != row.summary
      fields << "location"    if remote.location != row.location
      fields << "description" if remote.description.present?
      fields << "start_time"  if time_changed?(remote_start, row.start_time)
      fields << "end_time"    if time_changed?(remote_end, row.end_time)

      Rails.logger.info "User edit detected - Fields: #{fields.join(', ')}" if fields.any?
      fields
    end

    def recurrence_changed?
      self.class.normalize_recurrence(remote.recurrence) != self.class.normalize_recurrence(row.recurrence)
    end

    # The event data with the person's value in place of each edited field.
    def merge(event_data, fields)
      merged = event_data.dup
      fields.each do |field|
        case field
        when "summary"     then merged[:summary]     = remote.summary
        when "location"    then merged[:location]    = remote.location
        when "description" then merged[:description] = remote.description
        when "start_time"  then merged[:start_time]  = remote_start
        when "end_time"    then merged[:end_time]    = remote_end
        end
      end
      merged
    end

    # The row columns that take the event as the person left it in Google.
    def remote_row_attributes
      event_data = { summary: remote.summary, location: remote.location, start_time: remote_start,
                     end_time: remote_end, recurrence: remote.recurrence }

      event_data.merge(event_data_hash: CalendarEvent.generate_data_hash(event_data), last_synced_at: Time.current)
    end

    private

    attr_reader :row, :remote

    def remote_start
      self.class.parse_time(remote.start)
    end

    def remote_end
      self.class.parse_time(remote.end)
    end

    def time_changed?(remote_time, row_time)
      return remote_time != row_time if remote_time.nil? || row_time.nil?

      remote_time.to_i != row_time.to_i
    end
  end
end
