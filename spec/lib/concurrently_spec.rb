# frozen_string_literal: true

require "rails_helper"

RSpec.describe Concurrently do
  describe ".map" do
    it "returns the results in the order of the items, not the order they finish" do
      results = described_class.map([ 0.03, 0.0, 0.015 ]) do |delay|
        sleep delay
        delay
      end

      expect(results).to eq([ 0.03, 0.0, 0.015 ])
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

      described_class.map((1..7).to_a, limit: 2) do
        now = running.increment
        peak.update { |current| [ current, now ].max }
        sleep 0.01
        running.decrement
      end

      expect(peak.value).to eq(2)
    end

    it "raises the error of the first item that failed, after the others finish" do
      finished = Concurrent::Array.new

      expect {
        described_class.map([ 1, 2, 3 ]) do |item|
          sleep 0.02 if item == 3
          raise ArgumentError, "item #{item}" if item >= 2

          finished << item
        end
      }.to raise_error(ArgumentError, "item 2")

      expect(finished).to eq([ 1 ])
    end

    it "does not start a later batch after a failure" do
      started = Concurrent::Array.new

      expect {
        described_class.map([ 1, 2, 3, 4 ], limit: 2) do |item|
          started << item
          raise "boom" if item == 1
        end
      }.to raise_error("boom")

      expect(started).to contain_exactly(1, 2)
    end

    it "returns an empty list for no items" do
      expect(described_class.map([]) { raise "never called" }).to eq([])
    end
  end
end
