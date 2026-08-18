# frozen_string_literal: true

module Types
  class SeasonEnum < BaseEnum
    description "Academic season"

    Term.seasons.each_key do |season|
      value season.upcase, season.capitalize, value: season
    end
  end
end
