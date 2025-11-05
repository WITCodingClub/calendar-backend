class AddEmbeddingToRmpRatings < ActiveRecord::Migration[8.1]
  def change
    add_column :rmp_ratings, :embedding, :vector, limit: 1536
  end
end
