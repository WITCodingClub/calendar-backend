# frozen_string_literal: true

# Runs work that waits on the network in parallel threads.
#
# Use it only for blocks that wait on I/O and share no state, such as a Banner
# request. Do not use it for database writes. Each block runs inside the Rails
# executor, and the calling thread lets the blocks autoload while it waits, so
# it is safe inside a request or a job.
module Concurrently
  # Calls the block with each item, up to `limit` at a time, and returns the
  # results in the order of `items`. It waits for every block in a batch, then
  # raises the error of the first item in that batch that failed. Later batches
  # do not start after a failure.
  def self.map(items, limit: items.size, &block)
    items.each_slice([ limit, 1 ].max).flat_map do |batch|
      threads = batch.map do |item|
        Thread.new do
          Thread.current.report_on_exception = false
          Rails.application.executor.wrap { block.call(item) }
        end
      end

      outcomes = ActiveSupport::Dependencies.interlock.permit_concurrent_loads do
        threads.map do |thread|
          [ thread.value, nil ]
        rescue StandardError => e
          [ nil, e ]
        end
      end

      outcomes.each { |_, error| raise error if error }
      outcomes.map(&:first)
    end
  end
end
