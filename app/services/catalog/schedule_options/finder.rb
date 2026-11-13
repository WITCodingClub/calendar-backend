# frozen_string_literal: true

module Catalog
  module ScheduleOptions
    # Builds and ranks the schedules for a list of courses in one term
    # (POST /api/v1/catalog/schedule_options, the find_schedules MCP tool),
    # or only counts them (POST /api/v1/catalog/schedule_options/count).
    #
    #   Catalog::ScheduleOptions::Finder.new({ term_uid: 202720, courses: [ { codes: [ "COMP 3350" ] } ] }).call
    #
    # Input reads the request, Candidates loads the sections and builds the
    # units, Search finds the schedules that keep the hard rules, Ranking
    # orders them by the soft rules, and Relax runs only when the count is 0.
    # A returned schedule keeps every rule of Catalog::ScheduleRules: no time
    # conflict, no missing linked partner, no cancelled section, and no course
    # twice. It is not a registration check: holds, restrictions, and
    # registration times are Banner's.
    class Finder
      # surface: "api" or "mcp", for the busy metric (Slots).
      def initialize(params, surface: "api")
        @input   = Input.new(params)
        @surface = surface
      end

      # Raises BusyError when every search slot is in use (Slots).
      def call
        Slots.run(surface: @surface) { build }
      end

      def count
        Slots.run(surface: @surface) do
          result = search
          { count: result.count, capped: result.capped }
        end
      end

      private

      def build
        result = search

        {
          term:        { uid: candidates.term.uid, name: candidates.term.name },
          count:       result.count,
          capped:      result.capped,
          schedules:   ranked(result.schedules),
          relax:       result.count.zero? ? relax : [],
          not_offered: candidates.not_offered
        }
      end

      def preferences = @input.preferences

      def candidates
        @candidates ||= Candidates.new(@input).call
      end

      def search
        Search.new(candidates.entries, preferences, budget: Budget.new, open_ids: candidates.open_ids).call
      end

      def relax
        Relax.new(candidates.entries, preferences, open_ids: candidates.open_ids).call
      end

      def ranked(schedules)
        Ranking.new(preferences).call(schedules, limit: @input.limit).each_with_index.map do |scored, index|
          {
            rank:       index + 1,
            score:      scored.score.round(2),
            crns:       scored.units.flat_map(&:crns).map(&:to_s),
            courses:    scored.units.map { |unit| { code: unit.code, crns: unit.crns.map(&:to_s) } },
            highlights: scored.highlights,
            avoid_hits: scored.avoid_hits,
            totals:     ScheduleRules.totals(scored.units.flat_map(&:sections))
          }
        end
      end
    end
  end
end
