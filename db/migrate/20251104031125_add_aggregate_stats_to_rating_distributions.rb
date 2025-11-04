class AddAggregateStatsToRatingDistributions < ActiveRecord::Migration[8.1]
  def change
    add_column :rating_distributions, :avg_rating, :decimal, precision: 3, scale: 2
    add_column :rating_distributions, :avg_difficulty, :decimal, precision: 3, scale: 2
    add_column :rating_distributions, :would_take_again_percent, :decimal, precision: 5, scale: 2
    add_column :rating_distributions, :num_ratings, :integer, default: 0
  end
end
