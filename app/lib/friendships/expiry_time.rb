# frozen_string_literal: true

module Friendships
  # Reads a friendship, friend group, or meeting link end date from the API or
  # the dashboard. All of them use this one rule:
  #
  # - A date with no time ("2026-12-01") means the end of that day in
  #   the school time zone (SchoolTimeZone).
  # - A date and time follows Friendships::OffsetTime: it must carry a UTC
  #   offset.
  #
  # The end of the day is 23:59:59 with no fraction, so the stored value and
  # the ISO 8601 output are the same.
  #
  # Friendships::ExpiryTime.parse("2026-12-01") # => 2026-12-01 23:59:59 EST
  # Friendships::ExpiryTime.parse("2026-12-01T12:00:00") # => nil
  module ExpiryTime
    DATE_ONLY  = /\A\d{4}-\d{2}-\d{2}\z/

    module_function

    # Returns a time in the app zone, or nil when the value does not follow the
    # rule above.
    def parse(value)
      value = value.to_s.strip

      return OffsetTime.parse(value) unless value.match?(DATE_ONLY)

      Date.iso8601(value).in_time_zone(SchoolTimeZone.zone).end_of_day.change(usec: 0).in_time_zone
    rescue Date::Error
      nil
    end
  end
end
