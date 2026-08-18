# frozen_string_literal: true

module Types
  class RmpRatingType < BaseObject
    description "Aggregate Rate My Professors statistics for an instructor"

    field :id, String, null: true
    field :avg_rating, Float, null: true
    field :avg_difficulty, Float, null: true
    field :num_ratings, Integer, null: true
    field :would_take_again_percent, Float, null: true
  end
end
