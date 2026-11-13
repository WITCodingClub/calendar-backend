# frozen_string_literal: true

module Catalog
  module ScheduleOptions
    # The student's answers. Hard rules remove a section or a schedule before
    # the search counts it: blocked, earliest, latest, day_off, and open_only.
    # Soft rules only rank: avoid, days, and breaks (Ranking).
    #
    # A time range ({ days, after, before }) covers a meeting on one of its
    # days that overlaps the time from `after` to `before`. Without `after`,
    # it starts at midnight. Without `before`, it runs to the end of the day.
    # Without `days`, it is on every day.
    class Preferences
      KEYS = %w[blocked avoid earliest latest day_off open_only days breaks].freeze
      RANGE_KEYS = %w[days after before].freeze

      # The hard rules that the relax step can drop, in the order it lists them.
      RELAXABLE = %i[day_off earliest latest blocked open_only].freeze

      DAY_OFF = %w[none any].freeze
      DAYS    = %w[fewer spread any].freeze
      BREAKS  = %w[tight lunch any].freeze

      MAX_RANGES = 10
      DAY_NAMES  = ScheduleRules::DAYS
      WEEKDAYS   = %w[monday tuesday wednesday thursday friday].freeze

      # A time range on some days, in HHMM. to is 2400 for the end of the day.
      TimeRange = Data.define(:days, :from, :to) do
        def covers?(slot)
          days.include?(slot.day_of_week) && slot.begin_time < to && slot.end_time > from
        end
      end

      DEFAULTS = { blocked: [], avoid: [], earliest: nil, latest: nil, day_off: "none",
                   open_only: false, days: "any", breaks: "any" }.freeze

      attr_reader(*DEFAULTS.keys)

      # @param raw [Hash, nil] string keys
      def self.parse(raw)
        return new if raw.nil?
        raise FilterError, "preferences must be an object" unless raw.is_a?(Hash)

        unknown = raw.keys - KEYS
        raise FilterError, "Unknown preference(s): #{unknown.join(', ')}" if unknown.any?

        new(
          blocked:   parse_ranges(raw["blocked"], "blocked"),
          avoid:     parse_ranges(raw["avoid"], "avoid"),
          earliest:  parse_time(raw["earliest"], "earliest"),
          latest:    parse_time(raw["latest"], "latest"),
          day_off:   parse_day_off(raw["day_off"]),
          open_only: parse_boolean(raw["open_only"], "open_only"),
          days:      parse_choice(raw["days"], DAYS, "days"),
          breaks:    parse_choice(raw["breaks"], BREAKS, "breaks")
        )
      end

      def initialize(**values)
        values = DEFAULTS.merge(values)
        values.each { |key, value| instance_variable_set(:"@#{key}", value) }
        @values = values.freeze
        if earliest && latest && earliest >= latest
          raise FilterError, "earliest must be before latest"
        end
      end

      # The same answers with one hard rule dropped.
      def without(key) = self.class.new(**@values, key => DEFAULTS.fetch(key))

      # The hard rules that this request sets.
      def relaxable
        RELAXABLE.select { |key| @values[key] != DEFAULTS[key] }
      end

      def day_off_any? = day_off == "any"

      def free_days = day_off.is_a?(Array) ? day_off : []

      # True when every section of the unit keeps the hard rules for one
      # section. A pinned section keeps its place when it is full: the
      # student already picked it.
      def allows?(unit, open_ids)
        unit.members.all? { |member| allows_member?(member, open_ids) }
      end

      # Meetings that fall in an avoid range.
      def avoid_hits(slots)
        return 0 if avoid.empty?

        slots.count { |slot| avoid.any? { |range| range.covers?(slot) } }
      end

      def soft? = avoid.any? || days != "any" || breaks != "any"

      # A label for the relax step: what the student allows when the rule goes.
      def relax_label(key)
        case key
        when :day_off   then day_off_any? ? "Allow classes every weekday" : "Allow classes on #{list(day_off.map { |day| day.capitalize })}"
        when :earliest  then "Allow classes before #{Ranking.clock(earliest)}"
        when :latest    then "Allow classes after #{Ranking.clock(latest)}"
        when :blocked   then "Allow classes in your blocked times"
        when :open_only then "Include full sections"
        end
      end

      private

      def allows_member?(member, open_ids)
        return false if open_only && !member.pinned && !open_ids.include?(member.course.id)

        member.slots.none? do |slot|
          (earliest && slot.begin_time < earliest) ||
            (latest && slot.end_time > latest) ||
            free_days.include?(slot.day_of_week) ||
            blocked.any? { |range| range.covers?(slot) }
        end
      end

      def list(words) = words.to_sentence(two_words_connector: " and ", last_word_connector: ", and ")

      class << self
        private

        def parse_ranges(value, name)
          return [] if value.nil?
          raise FilterError, "#{name} must be a list of time ranges" unless value.is_a?(Array)
          raise FilterError, "Give at most #{MAX_RANGES} #{name} ranges" if value.size > MAX_RANGES

          value.map { |range| parse_range(range, name) }
        end

        def parse_range(value, name)
          raise FilterError, "Each #{name} range must be an object with days, after, or before" unless value.is_a?(Hash)

          unknown = value.keys - RANGE_KEYS
          raise FilterError, "Unknown #{name} key(s): #{unknown.join(', ')}" if unknown.any?
          raise FilterError, "Each #{name} range needs days, after, or before" if value.compact.empty?

          from = parse_time(value["after"], "#{name} after") || 0
          to   = parse_time(value["before"], "#{name} before") || 2400
          raise FilterError, "In a #{name} range, after must be before before" if from >= to

          TimeRange.new(days: value.key?("days") ? parse_days(value["days"], "#{name} days") : DAY_NAMES, from: from, to: to)
        end

        def parse_day_off(value)
          return "none" if value.nil?
          return value if DAY_OFF.include?(value)
          return parse_days(value, "day_off") if value.is_a?(Array) && value.any?

          raise FilterError, "day_off must be none, any, or a list of days"
        end

        def parse_days(value, name)
          days = value.is_a?(String) ? [ value ] : value
          raise FilterError, "#{name} must be a list of days" unless days.is_a?(Array) && days.any?

          days.map do |day|
            key = day.to_s.strip.downcase
            raise FilterError, "Unknown day #{day.inspect}" unless DAY_NAMES.include?(key)

            key
          end.uniq
        end

        def parse_time(value, name)
          return nil if value.nil?

          SectionQuery.parse_time(value)
        rescue FilterError
          raise FilterError, "Invalid #{name} time #{value.inspect}; use HH:MM"
        end

        def parse_boolean(value, name)
          case value
          when nil, false, "false", "0", 0 then false
          when true, "true", "1", 1 then true
          else raise FilterError, "Invalid #{name} #{value.inspect}; use true or false"
          end
        end

        def parse_choice(value, choices, name)
          return "any" if value.nil?
          return value if choices.include?(value)

          raise FilterError, "#{name} must be one of #{choices.join(', ')}"
        end
      end
    end
  end
end
