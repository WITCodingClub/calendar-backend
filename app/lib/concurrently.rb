# frozen_string_literal: true

# Runs work that waits on the network in parallel threads.
#
# Use it only for blocks that wait on I/O and share no state, such as a Banner
# request. Do not use it for database writes. Each block runs inside the Rails
# executor, and the calling thread lets the blocks autoload while it waits, so
# it is safe inside a request or a job.
module Concurrently
  # Calls the block with each item, on up to `limit` threads at a time, and
  # returns the results in the order of `items`. A thread takes the next item
  # as soon as it is free, so one slow item does not hold back the rest. After
  # a failure, no thread starts a new item. When the running items are done,
  # it raises the error of the first item (in the order of `items`) that
  # failed.
  #
  # Each thread gets a copy of the caller's ActiveSupport::ExecutionContext, so
  # code in the block still knows the job or the request it runs for (error
  # reports, and the Banner retry budget in Catalog::BannerThrottle).
  def self.map(items, limit: items.size, &block)
    return [] if items.empty?

    context = ActiveSupport::ExecutionContext.to_h
    queue   = Queue.new
    items.each_with_index { |item, index| queue << [ item, index ] }
    queue.close

    results = Array.new(items.size)
    errors  = Array.new(items.size)
    failed  = Concurrent::AtomicBoolean.new(false)

    workers = Array.new(limit.clamp(1, items.size)) do
      Thread.new do
        Thread.current.report_on_exception = false

        while !failed.true? && (entry = queue.pop)
          item, index = entry
          begin
            Rails.application.executor.wrap do
              ActiveSupport::ExecutionContext.set(**context) { results[index] = block.call(item) }
            end
          rescue StandardError => e
            errors[index] = e
            failed.make_true
          end
        end
      end
    end

    ActiveSupport::Dependencies.interlock.permit_concurrent_loads { workers.each(&:join) }

    error = errors.compact.first
    raise error if error

    results
  end
end
