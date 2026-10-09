# frozen_string_literal: true

module Friendships
  # Reads a friendship end date from the API or the dashboard. Both use this
  # one rule:
  #
  # - A date with no time ("2026-12-01") means the end of that day in
  #   America/New_York, the school's time zone.
  # - A date and time must carry a UTC offset ("2026-12-01T17:00:00-05:00" or
  #   "...Z"). A time with no offset is refused, because its meaning would depend
  #   on the server's time zone.
  #
  # The end of the day is 23:59:59 with no fraction, so the stored value and
  # the ISO 8601 output are the same.
  #
  # Friendships::ExpiryTime.parse("2026-12-01") # => 2026-12-01 23:59:59 EST
  # Friendships::ExpiryTime.parse("2026-12-01T12:00:00") # => nil
  module ExpiryTime
    ZONE       = "America/New_York"
    DATE_ONLY  = /\A\d{4}-\d{2}-\d{2}\z/
    # The same pattern as FriendMeetings::Creator::UTC_OFFSET.
    UTC_OFFSET = /(?:Z|[+-]\d{2}:?\d{2})\z/

    module_function

    # Returns a time in the app zone, or nil when the value does not follow the
    # rule above.
    def parse(value)
      value = value.to_s.strip

      if value.match?(DATE_ONLY)
        Date.iso8601(value).in_time_zone(ActiveSupport::TimeZone[ZONE]).end_of_day.change(usec: 0).in_time_zone
      elsif value.match?(UTC_OFFSET)
        Time.iso8601(value).in_time_zone
      end
    rescue ArgumentError
      nil
    end
  end
end
