# frozen_string_literal: true

class BusyBlocks
  # The dates of a busy-time request, checked once for the API routes
  # (Api::BusyBlocksParams) and the MCP tools (McpTools::BaseTool#date_range):
  # ISO dates, the end not before the start, and at most MAX_DAYS days.
  # BusyBlocks.new runs the same range check on dates from code.
  module DateRange
    # An ArgumentError, so BusyBlocks.new still raises one for a bad range.
    class InvalidError < ArgumentError; end

    module_function

    # [from, to]. A blank start_date is today, and a blank end_date is six
    # days after the start. Raises InvalidError with a message for the
    # person who asked.
    def parse(start_date, end_date)
      from = date(start_date, "start_date") || Time.zone.today
      to   = date(end_date, "end_date") || (from + 6)
      check!(from, to)

      [ from, to ]
    end

    def check!(from, to)
      raise InvalidError, "end_date must not be before start_date" if to < from
      raise InvalidError, "The range must be #{MAX_DAYS} days or fewer" if (to - from).to_i + 1 > MAX_DAYS
    end

    def date(value, name)
      return nil if value.blank?

      Date.iso8601(value.to_s)
    rescue Date::Error
      raise InvalidError, "#{name} must be a date in YYYY-MM-DD format"
    end
  end
end
