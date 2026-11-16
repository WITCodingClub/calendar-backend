# frozen_string_literal: true

module FriendMeetings
  # Turns the values of a create or update request into the types a
  # FriendMeeting takes. Raises FriendMeetings::Error for a value it cannot
  # read. The model checks the ranges.
  module RequestValues
    module_function

    def time(value, name)
      Friendships::OffsetTime.parse(value) || raise(Error, "#{name} must be an ISO 8601 time with a UTC offset")
    end

    def frequency(value)
      return value if FriendMeeting::FREQUENCIES.value?(value)

      raise Error, "frequency must be one of #{FriendMeeting::FREQUENCIES.values.join(', ')}"
    end

    def interval(value)
      return 1 if value.blank?
      raise Error, "repeat_interval must be a whole number" unless value.to_s.match?(/\A\d+\z/)

      value.to_i
    end

    # In lower case, without blanks or repeats. The model checks the names.
    def days(value)
      Array(value).map { |day| day.to_s.strip.downcase }.compact_blank.uniq
    end

    # nil, or an ISO 8601 date.
    def date(value, name)
      return nil if value.blank?

      Date.iso8601(value.to_s)
    rescue Date::Error
      raise Error, "#{name} must be an ISO 8601 date"
    end
  end
end
