# frozen_string_literal: true

module CourseCalendars
  # The repeat rule of an event and the days it skips.
  #
  # The calendar_events row keeps it as lines, "RRULE:FREQ=WEEKLY;UNTIL=...;BYDAY=MO"
  # and "EXDATE;TZID=America/New_York:20241128T090000", the form Google takes.
  # Every other reader (the ICS feed, Outlook, the sync's "fully past" check)
  # asks this object, so only #parse reads the lines.
  #
  # UNTIL is the end of the last day in SchoolTimeZone, as UTC, so the last
  # meeting of an evening class (after midnight UTC) stays in the series.
  class Recurrence
    # rule: the RRULE value with UNTIL, "FREQ=WEEKLY;UNTIL=20261205T045959Z;BYDAY=MO".
    # exdates: the start time of each skipped occurrence, in SchoolTimeZone.
    attr_reader :rule, :exdates

    # An IceCube rule that repeats until the end of last_day.
    def self.until_end_of(ice_cube_rule, last_day, exdates: [])
      until_time = SchoolTimeZone.zone.local(last_day.year, last_day.month, last_day.day, 23, 59, 59)
      new(ice_cube_rule.until(until_time.utc).to_ical, exdates)
    end

    # The value of a row's lines, or nil when they hold no RRULE.
    def self.parse(lines)
      lines = Array(lines).map(&:to_s)
      rrule = lines.find { |line| line.start_with?("RRULE:") }
      return nil unless rrule

      exdates = lines.select { |line| line.start_with?("EXDATE") }.flat_map do |line|
        line.split(":", 2).last.to_s.split(",").filter_map { |value| parse_exdate(value) }
      end
      new(rrule.delete_prefix("RRULE:"), exdates)
    end

    def self.parse_exdate(value)
      return SchoolTimeZone.zone.strptime(value[0, 15], "%Y%m%dT%H%M%S") if value.length >= 15

      SchoolTimeZone.zone.strptime(value[0, 8], "%Y%m%d")
    rescue ArgumentError
      nil
    end
    private_class_method :parse_exdate

    def initialize(rule, exdates = [])
      @rule    = rule
      @exdates = exdates
    end

    def lines
      [ "RRULE:#{rule}", *exdates.map { |time| "EXDATE;TZID=#{SchoolTimeZone::NAME}:#{time.strftime('%Y%m%dT%H%M%S')}" } ]
    end

    def frequency = parts["FREQ"]

    def interval = (parts["INTERVAL"] || 1).to_i

    # The BYDAY values: "MO", or "2WE" for a monthly rule.
    def days = parts["BYDAY"].to_s.split(",")

    def until_time
      Time.parse(parts["UNTIL"]) if parts["UNTIL"].present? # rubocop:disable Rails/TimeZone
    end

    def until_date
      until_time&.in_time_zone(SchoolTimeZone::NAME)&.to_date
    end

    def ended?
      until_time ? until_time.past? : false
    end

    def excluded_dates
      exdates.map(&:to_date).uniq
    end

    # The RRULE value for an iCalendar VEVENT. RFC 5545 needs a DATE UNTIL
    # when DTSTART is a DATE (an all-day event).
    def ical_rule(all_day:)
      return rule unless all_day && until_date

      rule.sub(/UNTIL=\d{8}T\d{6}Z/, "UNTIL=#{until_date.strftime('%Y%m%d')}")
    end

    def ==(other)
      other.is_a?(Recurrence) && other.lines == lines
    end

    private

    def parts
      @parts ||= rule.split(";").to_h { |part| part.split("=", 2) }
    end
  end
end
