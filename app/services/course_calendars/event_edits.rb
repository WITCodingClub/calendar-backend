# frozen_string_literal: true

module CourseCalendars
  # Compares a provider event with the values the app last wrote to it, which
  # the calendar_events row keeps, and finds the fields the person changed.
  #
  # Summary, location, start time and end time count when they differ. A
  # changed recurrence keeps the whole event as the person left it. The
  # description does not count: the app writes one to every event, and the row
  # does not store it, so the rule would freeze every description.
  class EventEdits
    def initialize(row, remote)
      @row    = row
      @remote = remote
    end

    def edited_fields
      fields = []
      # A provider leaves an empty field out of its answer, so nil and "" are
      # the same value here.
      fields << "summary"    if text_changed?(remote.summary, row.summary)
      fields << "location"   if text_changed?(remote.location, row.location)
      fields << "start_time" if time_changed?(remote_start, row.start_time)
      fields << "end_time"   if time_changed?(remote_end, row.end_time)

      Rails.logger.info({ message: "User edit detected", calendar_event_id: row.id, fields: fields }.to_json) if fields.any?
      fields
    end

    def recurrence_changed?
      remote.recurrence_changed
    end

    # The CourseCalendars::Event with the person's value in place of each edited field.
    def merge(event, fields)
      event.with(**remote_attributes.select { |field, _value| fields.include?(field.to_s) })
    end

    # The row values that describe the event as the person left it.
    def remote_attributes
      { summary: remote.summary, location: remote.location, start_time: remote_start, end_time: remote_end }
    end

    private

    attr_reader :row, :remote

    def text_changed?(remote_value, row_value)
      remote_value.to_s.strip != row_value.to_s.strip
    end

    def remote_start
      remote.start_time
    end

    # An all-day event ends at midnight after its last day. The app keeps a
    # time on the last day itself (CourseCalendars::Event#exclusive_end_date).
    def remote_end
      time = remote.end_time
      time && remote.all_day ? time - 1.day : time
    end

    def time_changed?(remote_time, row_time)
      return remote_time != row_time if remote_time.nil? || row_time.nil?
      return remote_time.to_date != row_time.in_time_zone(SchoolTimeZone::NAME).to_date if remote.all_day

      remote_time.to_i != row_time.to_i
    end
  end
end
