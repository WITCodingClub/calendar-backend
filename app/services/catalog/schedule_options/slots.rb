# frozen_string_literal: true

module Catalog
  module ScheduleOptions
    # Limits how many schedule searches run at the same time in one process,
    # for both routes and the find_schedules tool. Each search can use up to
    # its budget of CPU (Budget), so many addresses together could otherwise
    # take every Puma thread. Production runs one Puma process, so a limit in
    # the process is the right one.
    #
    # A search that finds no free slot does not wait: run raises BusyError at
    # once. The API answers 503 with Retry-After, and the tool answers with a
    # tool error. The relax step runs in the same request, so it uses the
    # same slot.
    module Slots
      # One thread fewer than Puma has, so one thread is always free for the
      # other requests. At least one slot.
      LIMIT = [ Integer(ENV.fetch("RAILS_MAX_THREADS", 3)) - 1, 1 ].max

      SEMAPHORE = Concurrent::Semaphore.new(LIMIT)

      # @param surface [String] "api" or "mcp", for the metric
      def self.run(surface:)
        unless SEMAPHORE.try_acquire
          Yabeda.calendar.schedule_builder_busy_total.increment({ surface: surface })
          raise BusyError, "The schedule builder is busy. Try again in a moment."
        end

        begin
          yield
        ensure
          SEMAPHORE.release
        end
      end
    end
  end
end
