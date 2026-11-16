# frozen_string_literal: true

module Friendships
  # An ISO 8601 time from a client of the friends features. It must carry a UTC
  # offset ("2026-12-01T17:00:00-05:00" or "...Z"). A time with no offset is
  # refused, because its meaning would depend on the server's time zone.
  # Friend meetings, meeting links and end dates read times with this rule.
  module OffsetTime
    PATTERN = /(?:Z|[+-]\d{2}:?\d{2})\z/

    module_function

    # A time in the app zone, or nil when the value does not follow the rule.
    def parse(value)
      value = value.to_s
      return nil unless value.match?(PATTERN)

      Time.iso8601(value).in_time_zone
    rescue ArgumentError
      nil
    end
  end
end
