# frozen_string_literal: true

module Catalog
  module ScheduleOptions
    # For a request with no schedule: each hard rule that the request sets,
    # with the count that the search gives without that one rule. A rule
    # whose removal still gives 0 is left out. The list has the higher count
    # first, then the order of Preferences::RELAXABLE.
    #
    # Each count is a search with no ranking. The rules share one more full
    # budget in equal parts, so one rule cannot use up the budget of the
    # others. A count that its part stopped is the lowest possible count.
    class Relax
      def initialize(entries, preferences, open_ids:)
        @entries     = entries
        @preferences = preferences
        @open_ids    = open_ids
      end

      def call
        keys = @preferences.relaxable
        options = keys.filter_map do |key|
          search = Search.new(@entries, @preferences.without(key), budget: Budget.share(keys.size), open_ids: @open_ids)
          count  = search.call.count
          { preference: key.to_s, label: @preferences.relax_label(key), count: count } if count.positive?
        end
        options.sort_by.with_index { |option, index| [ -option[:count], index ] }
      end
    end
  end
end
