# frozen_string_literal: true

require "rails_helper"

RSpec.describe Concurrently do
  describe ".map" do
    it "returns the results in the order of the items, not the order they finish" do
      fast_done = Concurrent::Event.new
      finish_order = Concurrent::Array.new

      results = described_class.map(%i[slow fast]) do |item|
        if item == :slow
          raise "the items ran one at a time" unless fast_done.wait(5)
        else
          fast_done.set
        end
        finish_order << item
        item
      end

      expect(finish_order).to eq(%i[fast slow])
      expect(results).to eq(%i[slow fast])
    end

    it "runs the items of a batch at the same time" do
      in_flight = Queue.new

      described_class.map(%i[a b c]) do |item|
        in_flight << item
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
        sleep 0.01 while in_flight.size < 3 && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        raise "items ran one at a time" if in_flight.size < 3
      end
    end

    it "never runs more than the limit at once" do
      running = Concurrent::AtomicFixnum.new(0)
      peak = Concurrent::AtomicFixnum.new(0)
      first_two = Concurrent::CountDownLatch.new(2)
      over_limit = Concurrent::Event.new

      described_class.map((1..7).to_a, limit: 2) do |item|
        now = running.increment
        peak.update { |current| [ current, now ].max }
        over_limit.set if now > 2
        if item <= 2
          # Hold the first two items together, and give a third thread time to
          # start if the limit does not hold.
          first_two.count_down
          first_two.wait(5)
          over_limit.wait(0.1)
        end
        running.decrement
      end

      expect(peak.value).to eq(2)
    end

    it "raises the error of the first item that failed, after the others finish" do
      all_started = Concurrent::CountDownLatch.new(3)
      third_failed = Concurrent::Event.new
      finished = Concurrent::Array.new

      expect {
        described_class.map([ 1, 2, 3 ]) do |item|
          all_started.count_down
          all_started.wait(5)

          if item == 3
            third_failed.set
            raise ArgumentError, "item 3"
          end

          third_failed.wait(5)
          raise ArgumentError, "item 2" if item == 2

          finished << item
        end
      }.to raise_error(ArgumentError, "item 2")

      expect(finished).to eq([ 1 ])
    end

    it "starts no new item after a failure" do
      both_started = Concurrent::CountDownLatch.new(2)
      failing_thread = Concurrent::AtomicReference.new
      started = Concurrent::Array.new

      expect {
        described_class.map([ 1, 2, 3, 4 ], limit: 2) do |item|
          started << item
          next unless item <= 2

          both_started.count_down
          both_started.wait(5)
          if item == 1
            failing_thread.set(Thread.current)
            raise "boom"
          end

          # The failing thread ends only after it marks the failure.
          Thread.pass until failing_thread.get
          failing_thread.get.join(5)
        end
      }.to raise_error("boom")

      expect(started).to contain_exactly(1, 2)
    end

    # A slow item must not hold back the items after it, as a fixed batch would.
    it "starts the next item as soon as a thread is free" do
      third_started = Concurrent::Event.new

      described_class.map([ :slow, :fast, :third ], limit: 2) do |item|
        third_started.set if item == :third
        raise "the third item waited for the slow one" if item == :slow && !third_started.wait(5)
      end
    end

    it "returns an empty list for no items" do
      expect(described_class.map([]) { raise "never called" }).to eq([])
    end
  end

  it "gives each thread the caller's execution context" do
    job = Object.new

    seen = ActiveSupport::ExecutionContext.set(job: job) do
      described_class.map([ 1, 2 ]) { ActiveSupport::ExecutionContext.to_h[:job] }
    end

    expect(seen).to eq([ job, job ])
  end
end
