# frozen_string_literal: true

module Catalog
  module ScheduleOptions
    # Finds the schedules that keep the hard rules: one unit from each course
    # entry, with no clash between two units (Unit#clashes?).
    #
    # 1. Each entry keeps the units whose sections pass the hard rules for a
    #    section (Preferences#allows?).
    # 2. The entry with the fewest units comes first, so a dead end shows
    #    early.
    # 3. A depth-first search adds one unit at a time and drops a branch at
    #    the first clash. With day_off "any", it also drops a branch that
    #    has a meeting on every weekday.
    # 4. It stops after CAP schedules, or when the budget is used up. Both
    #    set capped: the count is then the lowest possible count, and the
    #    ranking sees only the schedules found. The unit order of step 1
    #    makes those the likely best ones.
    class Search
      CAP = 500

      # schedules: lists of units in the order of the request's entries.
      Result = Data.define(:schedules, :capped) do
        def count = schedules.size
      end

      def initialize(entries, preferences, budget:, open_ids:)
        @entries     = entries
        @preferences = preferences
        @budget      = budget
        @open_ids    = open_ids
      end

      def call
        lists = @entries.map { |entry| allowed_units(entry) }
        return Result.new(schedules: [], capped: false) if lists.empty? || lists.any?(&:empty?)

        @found  = []
        @capped = false
        catch(:stop) { walk(lists.sort_by.with_index { |list, index| [ list.size, index ] }, 0, [], 0) }
        Result.new(schedules: @found, capped: @capped)
      end

      private

      # The units that pass the hard rules, the ones that look best for the
      # soft rules first, so a capped search finds the better schedules
      # first: fewer meetings in avoid ranges, fewer or more days (days), and
      # fewer meetings at lunch time (breaks: lunch). The CRNs break a tie, so
      # the order stays fixed for the same request.
      def allowed_units(entry)
        entry.units.select { |unit| @preferences.allows?(unit, @open_ids) }.sort_by { |unit| order_key(unit) }
      end

      LUNCH = Preferences::TimeRange.new(days: ScheduleRules::DAYS, from: 1130, to: 1300)

      def order_key(unit)
        days = unit.slots.map(&:day_of_week).uniq.size
        [
          @preferences.avoid_hits(unit.slots),
          { "fewer" => days, "spread" => -days }.fetch(@preferences.days, 0),
          @preferences.breaks == "lunch" ? unit.slots.count { |slot| LUNCH.covers?(slot) } : 0,
          unit.crns
        ]
      end

      def walk(lists, depth, chosen, mask)
        if depth == lists.size
          stop! if @found.size >= CAP
          @found << chosen.sort_by(&:entry_index)
          return
        end

        lists[depth].each do |unit|
          stop! unless @budget.spend!

          days = mask | unit.weekday_mask
          next if @preferences.day_off_any? && days == Unit::ALL_WEEKDAYS
          next if chosen.any? { |other| unit.clashes?(other) }

          chosen.push(unit)
          walk(lists, depth + 1, chosen, days)
          chosen.pop
        end
      end

      def stop!
        @capped = true
        throw :stop
      end
    end
  end
end
