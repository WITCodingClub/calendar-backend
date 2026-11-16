# frozen_string_literal: true

module Catalog
  # Reads the filter values of a catalog request: booleans, days, and times.
  # The query objects, the REST controllers, the MCP tools, and the schedule
  # builder use these readers, so one value means the same on every surface.
  # A value that cannot be read raises FilterError, which the public API
  # turns into a 400.
  module Params
    STRICT_BOOLEANS = { "true" => true, "1" => true, "false" => false, "0" => false }.freeze

    module_function

    # Any value other than a false one ("false", "0", "off", false) is true,
    # and blank is false. The query flags (semantic, include_cancelled,
    # active) read their values this way.
    def boolean(value)
      ActiveModel::Type::Boolean.new.cast(value).present?
    end

    # true, false, 1, or 0. Blank is nil. Any other value raises FilterError.
    # The seat filters and the schedule builder document this rule.
    def strict_boolean(value, name)
      return nil if value.nil? || value.to_s.strip.empty?

      STRICT_BOOLEANS.fetch(value.to_s.strip.downcase) do
        raise FilterError, "Invalid #{name} #{value.inspect}; use true or false"
      end
    end

    # A day name, such as "monday", in lowercase.
    def day(value)
      key = value.to_s.strip.downcase
      raise FilterError, "Unknown day #{value.inspect}" unless ScheduleRules::DAYS.include?(key)

      key
    end

    # "HH:MM", "HHMM", or an integer, as the HHMM integer that the
    # course_meeting_times columns store. Blank is nil.
    def time(value, name = "time")
      return nil if value.blank?

      Hhmm.parse(value) || raise(FilterError, "Invalid #{name} #{value.inspect}; use HH:MM or HHMM")
    end
  end
end
