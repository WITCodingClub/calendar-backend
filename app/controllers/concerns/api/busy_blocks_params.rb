# frozen_string_literal: true

module Api
  # Reads start_date and end_date for the busy-block routes
  # (BusyBlocks::DateRange). It renders a 400 and returns nil when the range
  # is not valid.
  module BusyBlocksParams
    extend ActiveSupport::Concern

    private

    def busy_blocks_range
      BusyBlocks::DateRange.parse(params[:start_date], params[:end_date])
    rescue BusyBlocks::DateRange::InvalidError => e
      render_error e.message, status: :bad_request
      nil
    end
  end
end
