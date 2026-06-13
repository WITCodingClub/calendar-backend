class CreateRatingDistributions < ActiveRecord::Migration[8.1]
  def change
    create_table :rating_distributions do |t|
      t.references :faculty, null: false, foreign_key: true, index: { unique: true }
      t.decimal :avg_rating, precision: 3, scale: 2
      t.decimal :avg_difficulty, precision: 3, scale: 2
      t.decimal :would_take_again_percent, precision: 5, scale: 2
      t.integer :num_ratings, default: 0
      t.integer :total, default: 0
      t.integer :r1, default: 0
      t.integer :r2, default: 0
      t.integer :r3, default: 0
      t.integer :r4, default: 0
      t.integer :r5, default: 0
      t.timestamps
    end
  end
end
