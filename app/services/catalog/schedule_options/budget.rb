# frozen_string_literal: true

module Catalog
  module ScheduleOptions
    # The most work that one search may do. The search spends one node for
    # each unit that it tries. The node count is the normal stop, so the same
    # request gives the same answer. The clock is a backstop for a slow
    # server: a hostile input cannot hold a Puma thread for long. The main
    # search gets one budget, and the relax step one more, split between its
    # rules (Relax).
    class Budget
      NODES   = 30_000
      SECONDS = 0.25
      # The clock is read once in this many nodes.
      CLOCK_EVERY = 256

      # A share of the full budget, for one of several searches.
      def self.share(parts) = new(nodes: NODES / parts, seconds: SECONDS / parts)

      def initialize(nodes: NODES, seconds: SECONDS)
        @nodes_left = nodes
        @deadline   = now + seconds
        @exhausted  = false
      end

      # Spends one node. False when the budget is used up.
      def spend!
        return false if @exhausted

        @nodes_left -= 1
        @exhausted = @nodes_left.negative? || ((@nodes_left % CLOCK_EVERY).zero? && now > @deadline)
        !@exhausted
      end

      def exhausted? = @exhausted

      private

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
