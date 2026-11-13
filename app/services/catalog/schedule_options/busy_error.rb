# frozen_string_literal: true

module Catalog
  module ScheduleOptions
    # Every search slot is in use (Slots). Not a FilterError: the request is
    # good, and the same request works a moment later.
    class BusyError < StandardError; end
  end
end
