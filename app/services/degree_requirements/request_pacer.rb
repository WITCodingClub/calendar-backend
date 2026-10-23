# frozen_string_literal: true

module DegreeRequirements
  # Waits so that two requests are at least `delay` seconds apart. The
  # clients use it so an import of a whole year does not load the site.
  class RequestPacer
    def initialize(delay)
      @delay = delay
      @last_at = nil
    end

    def wait
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      if @last_at && @delay.positive?
        remaining = @delay - (now - @last_at)
        sleep(remaining) if remaining.positive?
      end
      @last_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
