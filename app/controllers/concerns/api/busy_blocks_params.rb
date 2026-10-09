# frozen_string_literal: true

module Api
  # Reads and checks start_date and end_date for the busy-block routes. It
  # renders a 400 and returns nil when a date is not valid.
  module Api::BusyBlocksParams
    extend ActiveSupport::Concern

    private

    # start_date defaults to today and end_date to six days after start_date.
    def busy_blocks_range
      from = parse_date_param(:start_date) || Time.zone.today
      return if performed?

      to = parse_date_param(:end_date) || (from + 6)
      return if performed?

      if to < from
        render json: { error: "end_date must not be before start_date" }, status: :bad_request
        return
      end

      if (to - from).to_i + 1 > BusyBlocks::MAX_DAYS
        render json: { error: "The range must be #{BusyBlocks::MAX_DAYS} days or fewer" }, status: :bad_request
        return
      end

      [ from, to ]
    end

    def parse_date_param(name)
      value = params[name]
      return nil if value.blank?

      Date.iso8601(value.to_s)
    rescue Date::Error
      render json: { error: "#{name} must be a date in YYYY-MM-DD format" }, status: :bad_request
      nil
    end
  end
end
