# frozen_string_literal: true

module Catalog
  module ScheduleOptions
    # The sections that one course entry adds to a schedule: one section and
    # one option group of its linked partners (a lecture and its lab), or one
    # section that needs no partner. Candidates builds only units that keep
    # Catalog::ScheduleRules inside themselves, so the search only has to
    # check one unit against another.
    class Unit
      WEEKDAY_BITS = Preferences::WEEKDAYS.each_with_index.to_h { |day, index| [ day, 1 << index ] }.freeze
      ALL_WEEKDAYS = WEEKDAY_BITS.values.sum

      attr_reader :entry_index, :code, :members, :crns, :slots, :keys, :weekday_mask

      def initialize(entry_index:, code:, members:)
        @entry_index  = entry_index
        @code         = code
        @members      = members.sort_by { |member| member.course.crn }
        @crns         = @members.map { |member| member.course.crn }
        @slots        = @members.flat_map(&:slots)
        @keys         = @members.map { |member| ScheduleRules.duplicate_key(member.course) }
        @weekday_mask = @slots.reduce(0) { |mask, slot| mask | WEEKDAY_BITS.fetch(slot.day_of_week, 0) }
      end

      def sections = members.map(&:course)

      # True when the two units cannot be taken together: the same course
      # twice (or the same section) or a time conflict.
      def clashes?(other)
        keys.intersect?(other.keys) ||
          slots.any? { |x| other.slots.any? { |y| ScheduleRules.overlap?(x, y) } }
      end
    end
  end
end
