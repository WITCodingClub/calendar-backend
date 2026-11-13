# frozen_string_literal: true

module Catalog
  module ScheduleOptions
    # Scores each schedule from the soft rules and gives it highlights.
    #
    # The score is the mean of one part for each soft rule that the request
    # sets. Each part is from 0 to 1, so the score is too. With no soft rule,
    # every schedule scores 1.
    #
    # | Rule | Part |
    # | avoid | 1 / (1 + meetings in an avoid range) |
    # | days: fewer | (5 - days with classes) / 4, at least 0 |
    # | days: spread | the mean of (weekdays with classes / 5) and (shortest class day / longest class day, in minutes) |
    # | breaks: tight | 1 / (1 + hours between classes in all days) |
    # | breaks: lunch | the share of class days with 30 free minutes from 11:00 to 14:00 |
    #
    # Order: the higher score first, then fewer avoid hits, then the lower
    # CRN list. The same request always gives the same order.
    #
    # The day rules read every meeting of a day, also when two half-term
    # sections meet in different halves of the term.
    class Ranking
      LUNCH_FROM    = 11 * 60
      LUNCH_TO      = 14 * 60
      LUNCH_MINUTES = 30
      DONE_BY_LATEST       = 1700 # "Done by" only when the last class ends by 17:00
      NO_EARLY_FROM        = 1000 # "No classes before" only from 10:00
      MAX_HIGHLIGHTS       = 4

      Scored = Data.define(:units, :score, :avoid_hits, :highlights)

      # "9 AM", "1:30 PM".
      def self.clock(hhmm)
        hour, minute = hhmm.divmod(100)
        suffix = hour < 12 || hour == 24 ? "AM" : "PM"
        hour12 = ((hour - 1) % 12) + 1
        minute.zero? ? "#{hour12} #{suffix}" : format("%d:%02d %s", hour12, minute, suffix)
      end

      def initialize(preferences)
        @preferences = preferences
      end

      # @return [Array<Scored>] the best `limit` schedules, best first
      def call(schedules, limit:)
        schedules.map { |units| score(units) }
                 .sort_by { |scored| [ -scored.score.round(6), scored.avoid_hits, scored.units.flat_map(&:crns) ] }
                 .first(limit)
      end

      private

      def score(units)
        week  = Week.new(units.flat_map(&:slots))
        hits  = @preferences.avoid_hits(week.slots)
        parts = []
        parts << 1.0 / (1 + hits) if @preferences.avoid.any?
        parts << days_part(week) unless @preferences.days == "any"
        parts << breaks_part(week) unless @preferences.breaks == "any"

        Scored.new(units: units, score: parts.empty? ? 1.0 : parts.sum / parts.size,
                   avoid_hits: hits, highlights: highlights(week, hits))
      end

      def days_part(week)
        count = week.days.size
        return [ (5 - count) / 4.0, 0.0 ].max.clamp(0.0, 1.0) if @preferences.days == "fewer"

        loads = week.days.values.map { |intervals| intervals.sum { |from, to| to - from } }
        balance = loads.empty? || loads.max.zero? ? 1.0 : loads.min.to_f / loads.max
        ((week.weekdays.size / 5.0) + balance) / 2
      end

      def breaks_part(week)
        return 1.0 / (1 + (week.gap_minutes / 60.0)) if @preferences.breaks == "tight"
        return 1.0 if week.days.empty?

        week.days.count { |_day, intervals| Week.lunch?(intervals) } / week.days.size.to_f
      end

      # Short statements that are true of the schedule.
      def highlights(week, hits)
        return [] if week.slots.empty?

        list = []
        free = Preferences::WEEKDAYS - week.weekdays
        list << "#{free.map { |day| "#{day.capitalize}s" }.to_sentence(last_word_connector: ' and ')} off" if free.any? && free.size < 5
        list << "Lunch break every day" if week.days.all? { |_day, intervals| Week.lunch?(intervals) }
        list << "Done by #{self.class.clock(round_up_to_hour(week.latest_end))}" if week.latest_end <= DONE_BY_LATEST
        list << "No classes before #{self.class.clock((week.earliest_start / 100) * 100)}" if week.earliest_start >= NO_EARLY_FROM
        list << "No classes in times to avoid" if @preferences.avoid.any? && hits.zero?
        list.first(MAX_HIGHLIGHTS)
      end

      def round_up_to_hour(hhmm) = (hhmm % 100).zero? ? hhmm : ((hhmm / 100) + 1) * 100

      # The meetings of one schedule by day, as merged minute intervals.
      class Week
        attr_reader :slots, :days

        def initialize(slots)
          @slots = slots
          @days  = slots.group_by(&:day_of_week).transform_values { |list| merge(list) }
        end

        def weekdays = Preferences::WEEKDAYS.select { |day| days.key?(day) }

        def earliest_start = slots.map(&:begin_time).min
        def latest_end = slots.map(&:end_time).max

        # Minutes between classes on the same day, in all days.
        def gap_minutes
          days.values.sum { |intervals| intervals.each_cons(2).sum { |(_, end_a), (start_b, _)| start_b - end_a } }
        end

        # True when the day has 30 free minutes from 11:00 to 14:00.
        def self.lunch?(intervals)
          cursor = LUNCH_FROM
          intervals.each do |from, to|
            break if from >= LUNCH_TO
            return true if [ from, LUNCH_TO ].min - cursor >= LUNCH_MINUTES

            cursor = [ cursor, to ].max
          end
          LUNCH_TO - cursor >= LUNCH_MINUTES
        end

        private

        def minutes(hhmm) = ((hhmm / 100) * 60) + (hhmm % 100)

        def merge(list)
          list.map { |slot| [ minutes(slot.begin_time), minutes(slot.end_time) ] }.sort.each_with_object([]) do |(from, to), merged|
            if merged.any? && from <= merged.last[1]
              merged.last[1] = [ merged.last[1], to ].max
            else
              merged << [ from, to ]
            end
          end
        end
      end
    end
  end
end
